// fastVEP (https://github.com/Huang-lab/fastVEP, romualdomf/fastvep on Docker Hub)
// annotation, replacing Ensembl VEP.
//
// Design notes:
// - The fastvep image does not ship bcftools or htslib (bgzip/tabix), so
//   contig splitting (see prepare_annotation_input) and compressing/indexing
//   the annotated output (see compress_annotated_vcf) both run in the
//   pipeline's default container (which already carries bcftools/tabix, see
//   concat_vcfs in modules/local/common.nf) -- only the actual `fastvep
//   annotate` call runs inside the fastvep_annotation-labelled container.
// - `--gff3`/`--sa-dir` point at externally-prepared fastVEP cache data (gene
//   models + supplementary annotation .osa/.osa2 databases, see
//   params.fastvep_gff3/fastvep_sa_dir in nextflow.config) -- large, shared,
//   external directories, not something Nextflow's normal per-task file
//   staging is meant for. They are bind-mounted directly into the container
//   at the same absolute path on host and guest (see base.config,
//   withLabel:fastvep_annotation containerOptions). Unlike the VEP cache they
//   replace, this data isn't downloaded/managed by the pipeline itself --
//   populate it yourself (fastvep sa-build, etc.) before running.
// - `--fasta` reuses the same reference already passed around everywhere else
//   in the pipeline (the `reference` tuple below, same shape as ref_channel in
//   main.nf) rather than a separate fastvep-specific param -- it's staged into
//   the task work dir like any other Nextflow input, no bind mount needed.
// - fastvep writes plain text regardless of the `--output` file's extension
//   (no bgzip writer of its own, unlike VEP) -- run_fastvep always hands off a
//   plain-text VCF (decompressing the passthrough case with `zcat`, which
//   reads bgzip output fine), and compress_annotated_vcf bgzips/tabixes it
//   afterwards in the default container.
// - `annotate_vcf` is a workflow with the same name and output as the process
//   it replaces in modules/local/common.nf, so main.nf / wf-human-cnv.nf /
//   wf-human-sv.nf only need to change how they call it by adding the new
//   `reference` input fastVEP needs (VEP never took a fasta at all).


process prepare_annotation_input {
    // split the input VCF down to a single contig (SNP path, annotated
    // per-contig for parallelism) or pass the whole file through unchanged
    // (SV/CNV path, marked with contig == '*').
    cpus 1
    memory 2.GB
    input:
        tuple val(xam_meta), path("input.vcf.gz"), path("input.vcf.gz.tbi"), val(contig)
        val(output_label)
    output:
        tuple val(xam_meta), path("prepared.vcf.gz"), env(FULL_OUTPUT_LABEL), emit: prepared
    script:
        """
        if [ "${contig}" == '*' ]; then
            cp input.vcf.gz prepared.vcf.gz
            FULL_OUTPUT_LABEL="${output_label}"
        else
            bcftools view -r ${contig} input.vcf.gz | bgzip > prepared.vcf.gz
            FULL_OUTPUT_LABEL="${output_label}.${contig}"
        fi
        """
}


process run_fastvep {
    // runs functional consequence + supplementary annotation (whatever
    // params.fastvep_sa_dir has been built with -- ClinVar/gnomAD/dbSNP/etc)
    // + ACMG-AMP classification with fastVEP, replacing Ensembl VEP. Falls
    // back to a plain passthrough for genomes other than hg19/hg38, same
    // behaviour as the VEP/SnpEff steps this replaces. Always hands off a
    // plain-text VCF -- compressing/indexing happens next, in
    // compress_annotated_vcf, outside this container (see design notes above).
    label "fastvep_annotation"
    cpus 4
    memory 8.GB
    input:
        tuple val(xam_meta), path("prepared.vcf.gz"), val(output_label)
        val(genome)
        tuple path(ref), path(ref_idx), path(ref_cache), env(REF_PATH)
    output:
        tuple val(xam_meta), path("annotated.vcf"), val(output_label), emit: annotated
    script:
        def acmg_flag = params.fastvep_acmg ? '--acmg' : ''
        def pick_flag = params.fastvep_pick ? '--pick' : ''
        def hgvs_flag = params.fastvep_hgvs ? '--hgvs' : ''
        """
        if [[ "${genome}" != "hg38" ]] && [[ "${genome}" != "hg19" ]]; then
            zcat prepared.vcf.gz > annotated.vcf
        else
            fastvep annotate --input prepared.vcf.gz --output annotated.vcf \
                --gff3 ${params.fastvep_gff3} \
                --fasta ${ref} \
                --sa-dir ${params.fastvep_sa_dir} \
                --output-format ${params.fastvep_output_format} \
                ${acmg_flag} ${pick_flag} ${hgvs_flag}
        fi
        """
}


process compress_annotated_vcf {
    // bgzip + tabix the plain-text VCF run_fastvep produced. Runs in the
    // pipeline's default container (bcftools/htslib), not fastvep_annotation
    // -- see design notes above.
    cpus 2
    memory 2.GB
    input:
        tuple val(xam_meta), path("annotated.vcf"), val(output_label)
    output:
        tuple val(xam_meta), path("${xam_meta.alias}.wf_${output_label}.vcf.gz"), path("${xam_meta.alias}.wf_${output_label}.vcf.gz.tbi"), emit: annot_vcf
    script:
        def out_name = "${xam_meta.alias}.wf_${output_label}.vcf.gz"
        """
        bgzip -c annotated.vcf > ${out_name}
        tabix -p vcf ${out_name}
        """
}


workflow annotate_vcf {
    take:
        vcf_contig_tuple  // tuple(xam_meta, vcf.gz, vcf.gz.tbi, contig)
        genome            // "hg38" / "hg19" / other
        output_label      // e.g. "snp", "sv", "cnv"
        reference         // tuple(ref, ref_idx, ref_cache, REF_PATH) -- same
                           // shape as ref_channel elsewhere, fastVEP's --fasta
    main:
        prepared = prepare_annotation_input(vcf_contig_tuple, output_label).prepared
        annotated = run_fastvep(prepared, genome, reference).annotated
        final_out = compress_annotated_vcf(annotated).annot_vcf
    emit:
        annot_vcf = final_out
}
