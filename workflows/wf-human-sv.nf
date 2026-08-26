include {
    sniffles2;
    filterCalls;
    sortVCF;
    getVersions;
    report;
} from "../modules/local/wf-human-sv.nf"
include {
    filterBenchmarkVcf;
    intersectBedWithTruthset;
    truvari;
} from "../modules/local/wf-human-sv-eval.nf"
include {
    haploblocks as haploblocks_sv;
    normalize_vcf as normalize_sv_vcf
} from '../modules/local/common.nf'
include {
    annotate_vcf as annotate_sv_vcf
} from '../modules/local/vep.nf'
include {
    annotsv;
    annotate_vcf_with_tsv
} from '../modules/local/annotsv.nf'

workflow bam {
    take:
        bam_channel
        reference
        target
        mosdepth_stats
        optional_file
        genome_build
        chromosome_codes
        workflow_params
    main:
        called = variantCall(bam_channel, reference, target, mosdepth_stats, optional_file, genome_build, chromosome_codes)

        // bcftools norm -m -any: splits multiallelic records and left-aligns
        // indels, same treatment normalize_vcf gives the SNP VCF (see
        // modules/local/common.nf) -- this becomes the always-published
        // <alias>.wf_sv.vcf.gz, independent of --annotation, so the annotated
        // output below (<alias>.wf_sv.annotated.vcf.gz) never shadows it under
        // the same filename.
        normalized = normalize_sv_vcf(reference.collect(), called.vcf.join(called.vcf_index), "sv").normalized_vcf

        // benchmark
        if (params.sv_benchmark) {
            maybe_benchmark_result = runBenchmark(normalized.map{meta, vcf, tbi -> [meta, vcf]}, reference, target)
        }
        else {
            maybe_benchmark_result = Channel.empty()
        }

        if (!params.annotation) {
            annotated_vcf = Channel.empty()
            annotsv_tsv = Channel.empty()

            report = runReport(
                normalized.map{meta, vcf, tbi -> [meta, vcf]}.groupTuple(),
                maybe_benchmark_result.ifEmpty(optional_file),
                workflow_params
            )
        }
        else {
            // append '*' to indicate that annotation should be performed on all chr at once.
            // Explicit reconstruction, not `it << '*'`: List.leftShift mutates the row
            // object in place and returns the same reference -- `normalized` has more
            // than one subscriber in this workflow (see the `output =` channel in
            // `emit:` below), and GPars broadcasts the same row object to every
            // subscriber rather than cloning it. Mutating it here raced with the other
            // subscriber's 3-param `.map{ meta, vcf, tbi -> ... }` closure reading that
            // same object elsewhere in the dataflow graph: whichever one ran second saw
            // a 4-element row where it expected 3, and Nextflow's `.map` operator won't
            // spread a row into a closure whose declared param count doesn't match it,
            // so it called the closure with the whole row as one argument instead --
            // Groovy has no `call()` overload for a 3-param closure taking one ArrayList,
            // so it raised a MissingMethodException. Non-deterministic (thread
            // scheduling-dependent): only reproduced on the CNV path, not the
            // structurally identical SV one, in the same run.
            vcf_for_annotation = normalized.map{ meta, vcf, tbi -> [meta, vcf, tbi, '*'] }
            // annotate with fastVEP -- <alias>.wf_sv.annotated.vcf.gz
            fastvep_vcf = annotate_sv_vcf(vcf_for_annotation, genome_build, "sv.annotated", reference.collect()).annot_vcf

            // optionally rank/annotate the SVs further with AnnotSV, and (on
            // top of that) write AnnotSV's own columns back into fastvep_vcf as
            // more INFO fields -- annotate_vcf_with_tsv reads fastvep_vcf and
            // rewrites it under the SAME <alias>.wf_sv.annotated.vcf.gz name
            // (not a separate file), so that filename always ends up being
            // "whatever annotation --annotation/--annotsv turned on", never two
            // competing files publishing under it.
            if (params.annotsv) {
                annotsv_result = annotsv(fastvep_vcf, genome_build, "sv").annotsv_tsv
                annotsv_tsv = annotsv_result.map{ meta, tsv -> tsv }
                annotated_vcf = annotate_vcf_with_tsv(annotsv_result, fastvep_vcf, "sv").annotated_vcf
            } else {
                annotsv_tsv = Channel.empty()
                annotated_vcf = fastvep_vcf
            }

            report = runReport(
                annotated_vcf.map{meta, vcf, tbi -> [meta, vcf]}.groupTuple(),
                maybe_benchmark_result.ifEmpty(optional_file),
                workflow_params
            )
        }

        // Prepare stuff to emit
        sv_stats_json = report.json
        report = report.html.concat(
            normalized.map{meta, vcf, tbi -> [vcf, tbi]},
            annotated_vcf.map{meta, vcf, tbi -> [vcf, tbi]},
            maybe_benchmark_result,
            annotsv_tsv
        )

    emit:
        report = report
        sv_stats_json = sv_stats_json
        sniffles_vcf = called.vcf
        for_phasing = params.annotation ? annotated_vcf : normalized
}


workflow runBenchmark {
    take:
        vcf
        reference
        target
    main:
        // for benchmarking we bundle a dataset in the SV container in $WFSV_EVAL_DATA_PATH
        // rather than coupling that dataset to the workflow by referring to it here
        //   in a value channel (or similar), we'll instead interpret use of dummy files
        //   as a flag to load from the bundled dataset inside the process scope
        // note we're not using the usual `optional_file` as this will cause an input collision error
        //   instead we just reference some OPTIONAL_FILE.ext that we know don't exist
        //   we can get away with this as the files will never be opened (so don't need to exist)

        // reconcile workflow target BED and benchmark truthset BED
        //   recall if user does not input a BED, one covering all genomic
        //   intervals in the ref is generated by getAllChromosomesBed
        if (params.sv_benchmark_bed) {
            truthset_bed = Channel.fromPath(params.sv_benchmark_bed, checkIfExists: true)
        }
        else {
            truthset_bed = file("OPTIONAL_FILE.bed") // this will trigger process to use bundled benchmark bed
        }
        intersected = intersectBedWithTruthset(target, truthset_bed)

        // load user-provided benchmark data
        if (params.sv_benchmark_vcf) {
            // truvari assumes index is [vcf].tbi
            truthset_vcf = Channel.fromPath(params.sv_benchmark_vcf, checkIfExists: true)
            truthset_tbi = Channel.fromPath(params.sv_benchmark_vcf + '.tbi', checkIfExists: true)
        }
        else {
            // we'll create some non-existent optional files to stage
            // again this will trigger the process to use the bundled benchmark data
            // we use channels here so we can concat them later
            truthset_vcf = Channel.fromPath("OPTIONAL_FILE.vcf.gz", checkIfExists: false)
            truthset_tbi = Channel.fromPath("OPTIONAL_FILE.vcf.gz.tbi", checkIfExists: false)
        }

        // run benchmark
        filtered = filterBenchmarkVcf(vcf)
        truvari(
            reference,
            filtered,
            truthset_vcf.concat(truthset_tbi).toList(),
            intersected.intersected_bed)
    emit:
        json = truvari.out.truvari_json
}


workflow variantCall {
    take:
        bam_channel
        reference
        target_bed
        mosdepth_stats
        optional_file
        genome_build
        chromosome_codes
    main:

        // tandom_repeat bed
        if(params.tr_bed) {
            tr_bed = Channel.fromPath(params.tr_bed, checkIfExists: true)
        } else {
            tr_bed = optional_file
        }

        if (!genome_build) {
            genome_build = Channel.of(null)
        }

        sniffles2(bam_channel, tr_bed, reference, genome_build)
        filterCalls(sniffles2.out.vcf, mosdepth_stats, target_bed, chromosome_codes)
        sortVCF(filterCalls.out.vcf)

    emit:
        vcf = sortVCF.out.vcf_gz
        vcf_index = sortVCF.out.vcf_tbi
}


workflow runReport {
    take:
        vcf
        eval_json
        workflow_params
    main:
        software_versions = getVersions()
        report(
            vcf,
            eval_json,
            software_versions,
            workflow_params
        )
    emit:
        html = report.out.html
        json = report.out.json
}
