include {
    callCNV;
    getVersions;
    add_snp_tools_to_versions;
    bgzip_and_index_vcf;
    makeReport
} from "../modules/local/wf-human-cnv.nf"

include {
    mosdepth;
    normalize_vcf as normalize_cnv_vcf
} from "../modules/local/common.nf"

include {
    annotate_vcf
} from "../modules/local/vep.nf"

include {
    annotsv
} from "../modules/local/annotsv.nf"

include {
    cnv_ensemble
} from "../modules/local/cnv_ensemble.nf"

workflow cnv {
    take:
        bam
        ref
        clair3_vcf
        bed
        genome_build
        workflow_params
    main:
        // get mosdepth results for window size 1000
        mosdepth(bam, bed, ref, "1000", false, "bed")
        mosdepth_stats = mosdepth.out.mosdepth_tuple.map{ meta, bed, dist, threshold -> [bed, dist, threshold]}
        mosdepth_summary = mosdepth.out.summary
        if (params.depth_intervals) {
            mosdepth_perbase = mosdepth.out.perbase
        } else {
            mosdepth_perbase = Channel.from("$projectDir/data/OPTIONAL_FILE")
        }

        mosdepth_all = mosdepth_stats.concat(mosdepth_summary).concat(mosdepth_perbase).collect()
        
        cnvs = callCNV(clair3_vcf, mosdepth_all, ref, genome_build)
        spectre_vcf = cnvs.spectre_vcf
        spectre_vcf_bgzipped = bgzip_and_index_vcf(spectre_vcf)
        spectre_bed = cnvs.spectre_bed
        spectre_karyotype = cnvs.spectre_karyotype

        // bcftools norm -m -any: same treatment normalize_vcf gives the SNP/SV
        // VCFs (see modules/local/common.nf) -- this becomes the
        // always-published <alias>.wf_cnv.vcf.gz, independent of --annotation,
        // so the annotated output below (<alias>.wf_cnv.annotated.vcf.gz) never
        // shadows it under the same filename.
        normalized = normalize_cnv_vcf(ref.collect(), spectre_vcf_bgzipped, "cnv").normalized_vcf

        // check if annotation has been requested
        if (!params.annotation) {
            annotated_vcf = Channel.empty()
            annotsv_tsv = Channel.empty()
            cnv_ensemble_tsv = Channel.empty()
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
            // annotate with fastVEP -- <alias>.wf_cnv.annotated.vcf.gz
            fastvep_vcf = annotate_vcf(vcf_for_annotation, genome_build, "cnv.annotated", ref.collect()).annot_vcf

            // optionally rank/annotate the CNVs further with AnnotSV, and (on top
            // of that) run the ISV/ClassifyCNV ensemble on AnnotSV's output --
            // when the ensemble step also runs it writes AnnotSV+ISV+ClassifyCNV
            // columns back into fastvep_vcf under the SAME
            // <alias>.wf_cnv.annotated.vcf.gz name (not a separate file); AnnotSV
            // alone (no ensemble) only produces the .wf_cnv.annotsv.tsv, same as
            // before -- the VCF itself stays fastVEP-only in that case.
            if (params.annotsv) {
                annotsv_result = annotsv(fastvep_vcf, genome_build, "cnv").annotsv_tsv
                annotsv_tsv = annotsv_result.map{ meta, tsv -> tsv }

                if (params.cnv_ensemble) {
                    ensemble_result = cnv_ensemble(annotsv_result, fastvep_vcf, genome_build)
                    cnv_ensemble_tsv = ensemble_result.annotated_tsv.map{ meta, tsv -> tsv }
                    annotated_vcf = ensemble_result.annotated_vcf
                } else {
                    annotated_vcf = fastvep_vcf
                    cnv_ensemble_tsv = Channel.empty()
                }
            } else {
                annotated_vcf = fastvep_vcf
                annotsv_tsv = Channel.empty()
                cnv_ensemble_tsv = Channel.empty()
            }
        }

        software_versions_tmp = getVersions()
        software_versions = add_snp_tools_to_versions(software_versions_tmp)
        if (params.output_report){
            report = makeReport(software_versions.collect(), workflow_params, spectre_bed, spectre_karyotype, genome_build)
        } else {
            report = Channel.empty()
        }

    emit:
        output = normalized.map{ meta, vcf, tbi -> [vcf, tbi]}
            .concat(annotated_vcf.map{ meta, vcf, tbi -> [vcf, tbi]}, report, annotsv_tsv, cnv_ensemble_tsv)
        cnv_vcf = params.annotation ? annotated_vcf : normalized
}