// Generates a per-run report.config (for interactive_report/report.py) at the end of a
// successful run, using interactive_report/report.config as the model: every line that
// isn't one of the run-specific keys below (sample/snv_vcf/sv_vcf/cnv_vcf/str_vcf/
// dmr_bed/bam) is copied verbatim -- select_columns/color_columns/color_palettes/
// column_filter are curated UI presets, not per-run data, so they're preserved exactly
// as they are in the template.
//
// Run from workflow.onComplete (see main.nf), not a Nextflow process: onComplete fires
// on the launching host only after Nextflow has confirmed every process AND its
// publishDir copy are done -- a process-based dependency can only guarantee process
// completion order, not that publishDir has actually finished copying into out_dir yet,
// and a containerized task wouldn't reliably see out_dir on the host filesystem anyway
// (it's not bind-mounted). onComplete sidesteps both problems.
class ReportConfig {

    // For snv/sv/cnv: the fastVEP-annotated VCF when --annotation produced one for that
    // flow, else the plain normalized VCF (see modules/local/vep.nf / normalize_vcf in
    // modules/local/common.nf) -- checked by file existence, not by trusting
    // params.annotation, since that's one global flag and a given flow might not have
    // run its own annotate_vcf call this time regardless of it.
    private static final Map<String, List<String>> CANDIDATES_TEMPLATE = [
        snv_vcf: ['%s.snv.annotated.vcf.gz', '%s.snv.vcf.gz'],
        sv_vcf : ['%s.sv.annotated.vcf.gz', '%s.sv.vcf.gz'],
        cnv_vcf: ['%s.cnv.annotated.vcf.gz', '%s.cnv.vcf.gz'],
        // STR never has an annotated variant (see forest.mdc, STR section) -- only one
        // candidate.
        str_vcf: ['%s.str.vcf.gz'],
        // DMR can produce up to 4 annotated tables per run (dmr_haplotype_compare and/or
        // dmr_sample_compare, each in 5mC and 5hmC -- see workflows/dmr.nf,
        // comparison_label). report.config only has room for one dmr_bed: prefer
        // sample_compare over haplotype_compare, and 5mC over 5hmC, within whichever
        // comparison(s) actually ran this session.
        dmr_bed: [
            '%s.mods.sample_compare.5mC.dmr_annotated.tsv',
            '%s.mods.sample_compare.5hmC.dmr_annotated.tsv',
            '%s.mods.haplotype_compare.5mC.dmr_annotated.tsv',
            '%s.mods.haplotype_compare.5hmC.dmr_annotated.tsv',
        ],
        // Haplotagged whole-genome alignment when haplotagging ran (str/phased/steller --
        // see run_haplotagging in main.nf), else the plain alignment output -- BAM or
        // CRAM depending on params.output_xam_fmt (see output_definition.json,
        // "alignment"/"haplotagged-alignment" entries).
        bam    : ['%s.haplotagged.bam', '%s.haplotagged.cram', '%s.bam', '%s.cram'],
    ]

    static void generate(params, projectDirPath) {
        File outDir = new File(params.out_dir as String).absoluteFile
        if (!outDir.isDirectory()) {
            return
        }
        File templateFile = new File(new File(projectDirPath as String), 'interactive_report/report.config')
        if (!templateFile.isFile()) {
            return
        }
        String sample = params.sample_name as String

        Map<String, String> resolved = [sample: sample]
        CANDIDATES_TEMPLATE.each { key, patterns ->
            resolved[key] = firstExisting(outDir, patterns.collect { String.format(it, sample) })
        }

        File templateDir = templateFile.parentFile
        File outFile = new File(outDir, 'report.config')
        outFile.withWriter { w ->
            templateFile.eachLine { line ->
                String trimmed = line.trim()
                if (trimmed.startsWith('#') || !trimmed.contains('=')) {
                    w.writeLine(line)
                    return
                }
                String key = trimmed.split('=', 2)[0].trim()
                if (resolved.containsKey(key)) {
                    w.writeLine("${key} = ${resolved[key]}")
                } else if (key == 'region') {
                    // Paths in report.config are resolved relative to the config file's
                    // own directory (see report.py's load_config) -- this new file lives
                    // in outDir, not next to the template, so a relative region value
                    // from the template must be turned absolute here (resolved against
                    // the TEMPLATE's own directory, same as report.py would have
                    // resolved it there) or it would silently point at the wrong place.
                    String value = trimmed.split('=', 2)[1].trim()
                    File regionFile = new File(value)
                    if (!regionFile.isAbsolute()) {
                        regionFile = new File(templateDir, value)
                    }
                    w.writeLine("region = ${regionFile.absolutePath}")
                } else {
                    w.writeLine(line)
                }
            }
        }
    }

    // First candidate filename that actually exists in outDir, as an absolute path --
    // absolute so this run's report.config keeps working regardless of the fact that
    // report.py resolves relative paths against the CONFIG file's own directory (which
    // is outDir here, so a bare filename would technically also work, but an explicit
    // absolute path removes any ambiguity if this file is later copied elsewhere).
    // Empty string (not a guess) when none of the candidates exist -- that flow simply
    // didn't run this session; report.py will raise a clear "missing key" error if this
    // config is ever used as-is, which is the correct behaviour, not a bug to work
    // around here.
    private static String firstExisting(File dir, List<String> names) {
        for (String name : names) {
            File f = new File(dir, name)
            if (f.isFile()) {
                return f.absolutePath
            }
        }
        return ''
    }
}
