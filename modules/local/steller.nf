// sTELLeR (https://github.com/KristineBilgrav/sTELLeR, kristinebilgrav/steller on Docker
// Hub) -- calls non-reference transposable element (Alu/L1/SVA/HERV) insertions from
// long-read alignments. Replaces tldr (removed) as this pipeline's transposable-element
// insertion caller. Runs per-contig, against the same intermediate haplotagged BAMs
// straglr's call_str already consumes (workflows/wf-human-snv.nf, the `str_bams` emit)
// -- i.e. the phase where alignment/haplotagging has already happened but the per-contig
// BAMs haven't been merged back into one whole-genome BAM yet -- same wiring point tldr
// used before it.
//
// `-o/--output` is a plain prefix, not a directory: steller.py always writes exactly one
// file, `<prefix>_repeats.vcf` (confirmed running the real image against a real BAM slice
// -- no directory tree, no other file). It's plain-text VCF, not bgzipped/indexed.
//
// steller.py has no --chroms/-c equivalent to restrict which contigs it scans -- unlike
// tldr, it always iterates every contig in the reference's own dictionary (confirmed: even
// fed a BAM containing only chr21 reads, the log still walks every alt/decoy contig in the
// reference, printing "no clusters found" for each). That's inherent to the tool, not
// something this integration can restrict from the outside -- each per-contig invocation
// pays that same fixed scan-the-whole-dictionary cost regardless of how small its own BAM
// is.
//
// No merge step across contigs: each per-contig VCF's sample column is literally the
// `-o` prefix string given to that invocation (confirmed: `-o /tmp/foo` produces a VCF
// whose sample column header is literally "/tmp/foo") -- since every contig gets a
// different prefix (see call_steller below), naively concatenating them would leave every
// per-contig VCF with a different, mismatched sample-column name. Reconciling that (e.g.
// via `bcftools reheader`) wasn't asked for, so per-contig VCFs are published as-is,
// unmerged -- see output_steller below.

process call_steller {
    // steller loads the whole reference + TE fasta + scans every contig in the
    // dictionary per invocation (see notes above) -- same OOM-prone shape as
    // run_fastvep/run_tapes/call_tldr, so it gets the same retry treatment.
    label "steller"
    cpus 2
    memory { MemoryScaling.forAttempt(MemoryScaling.SERIES_16, task.attempt, params.max_memory) }
    errorStrategy {task.exitStatus in [137, 140] ? 'retry' : 'finish'}
    maxRetries { MemoryScaling.retriesNeeded(MemoryScaling.SERIES_16, params.max_memory) }
    input:
        tuple path(xam), path(xam_idx), val(xam_meta)
        tuple path(ref), path(ref_idx), path(ref_cache), env(REF_PATH)
        path(te_fasta)
    output:
        tuple val(xam_meta.sq), path("*_repeats.vcf"), optional: true
    script:
        def chr = xam_meta.sq
        def outprefix = "${xam_meta.alias}.${chr}_steller"
        // -b/--bam, -R/--ref, -o/--output are wired internally by the pipeline (the
        // per-contig BAM channel, the same ref_channel used everywhere else, and a
        // deterministic per-contig prefix), same convention tldr used for
        // -b/-r/-o/-c. --style is always "ont" -- hardcoded, not a param, since this
        // pipeline only ever processes ONT data.
        """
        n_reads=\$(samtools view -c ${xam})
        if [[ "\$n_reads" -gt 0 ]]; then
            python /sTELLeR/steller/steller.py \
                --ref ${ref} \
                --TE_fasta ${te_fasta} \
                --bam ${xam} \
                --sr ${params.steller_sr} \
                --style ont \
                -o ${outprefix} \
                --maxreads ${params.steller_maxreads} \
                --mq ${params.steller_mq}
        else
            echo "no reads on ${chr}, skipping"
        fi
        """
}


// See https://github.com/nextflow-io/nextflow/issues/1636
// This is the only way to publish files from a workflow whilst
// decoupling the publish from the process steps.
process output_steller {
    // publish inputs to output directory -- same trivial passthrough as output_tldr
    // before it.
    label "wf_common"
    publishDir "${params.out_dir}", mode: 'copy', pattern: "*"
    input:
        path fname
    output:
        path fname
    script:
    """
    echo "Writing output files"
    """
}


workflow steller {
    take:
        bam_channel   // per-contig (xam, xam_idx, xam_meta) -- e.g. clair_vcf.str_bams
        ref_channel
    main:
        // turn ref/TE fasta into value channels so they can be reused across every
        // per-contig task, same idiom already used for ref_channel elsewhere.
        ref_as_value = ref_channel.collect()
        te_fasta_as_value = Channel.fromPath(params.steller_TE_fasta).collect()

        per_contig_vcfs = call_steller(bam_channel, ref_as_value, te_fasta_as_value)

    emit:
        output = per_contig_vcfs.map { sq, vcf -> vcf }
}
