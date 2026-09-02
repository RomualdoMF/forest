Output files may be aggregated including information for all samples or provided per sample. Per-sample files will be prefixed with respective aliases and represented below as {{ alias }}.

| Title | File path | Description | Per sample or aggregated |
|-------|-----------|-------------|--------------------------|
| Report of the alignment statistics | {{ alias }}.alignment-report.html | Report summarising the results of the alignment statistics for the sample. | per-sample |
| JSON file of some base statistics | {{ alias }}.stats.json | This JSON file contains base statistics on the reads, mappings, SNVs and SVs for the sample. | per-sample |
| Report of the SNV workflow | {{ alias }}.snv-report.html | Report summarising the results of the SNV subworkflow for the sample. | per-sample |
| Report of the SV workflow | {{ alias }}.sv-report.html | Report summarising the results of the SV subworkflow for the sample. | per-sample |
| Report of the CNV workflow | {{ alias }}.cnv-report.html | Report summarising the results of the CNV subworkflow for the sample. | per-sample |
| Report of the STR workflow | {{ alias }}.str-report.html | Report summarising the results of the short tandem repeat subworkflow for the sample. | per-sample |
| Short variant VCF | {{ alias }}.snv.vcf.gz | VCF file with the SNVs for the sample. | per-sample |
| Structural variant VCF | {{ alias }}.sv.vcf.gz | VCF file with the SVs for the sample. | per-sample |
| Structural variant SNF | {{ alias }}.sv.snf | SNF file with the SVs for the sample, for onward multi-sample SV calling. | per-sample |
| Copy number variants VCF | {{ alias }}.cnv.vcf.gz | VCF file with the CNV for the sample. | per-sample |
| Modified bases bedMethyl | {{ alias }}.mods.bedmethyl.gz | BED file with the aggregated modification counts for the sample. | per-sample |
| Modified bases bedMethyl (haplotype 1) | {{ alias }}.mods.1.bedmethyl.gz | BED file with the aggregated modification counts for haplotype 1 of the sample. | per-sample |
| Modified bases bedMethyl (haplotype 2) | {{ alias }}.mods.2.bedmethyl.gz | BED file with the aggregated modification counts for haplotype 2 of the sample. | per-sample |
| 5mC bigWig | {{ alias }}.mods.5mC.bw | bigWig for visualisation of aggregated 5mC modification counts. | per-sample |
| 5mC bigWig (haplotype 1) | {{ alias }}.mods.1-5mC.bw | bigWig for visualisation of aggregated 5mC modification counts for haplotype 1 of the sample. | per-sample |
| 5mC bigWig (haplotype 2) | {{ alias }}.mods.2-5mC.bw | bigWig for visualisation of aggregated 5mC modification counts for haplotype 2 of the sample. | per-sample |
| Short tandem repeat VCF | {{ alias }}.str.vcf.gz | VCF file with the STR sites for the sample. | per-sample |
| Alignment file | {{ alias }}.cram | CRAM or BAM file with the aligned reads for the sample, generated when the input file is unaligned. | per-sample |
| Alignment file index | {{ alias }}.cram.crai | The index of the resulting CRAM or BAM file with the reads for the sample, generated when the input file is unaligned. | per-sample |
| Haplotagged alignment file | {{ alias }}.haplotagged.cram | CRAM or BAM file of all input reads with haplotags added by phasing. | per-sample |
| Haplotagged alignment file index | {{ alias }}.haplotagged.cram.crai | The index of the resulting CRAM or BAM file produced when haplotags have been added by phasing. | per-sample |
| Mean coverage for each region | {{ alias }}.regions.bed.gz | The mean coverage in the individual regions of the genome in BED format. | per-sample |
| Coverage per region above the given thresholds | {{ alias }}.thresholds.bed.gz | The BED reporting the number of bases in each region that are covered at or above each threshold values (1x, 10x, 20x and 30x). | per-sample |
| Distribution of the proportion of total bases covered by a given coverage value | {{ alias }}.mosdepth.global.dist.txt | The cumulative distribution indicating the proportion of total bases covered by a given coverage value, both genome-wide and by sequence. | per-sample |
| Mean coverage per sequence and target region | {{ alias }}.mosdepth.summary.txt | The summary of mean depths per chromosome and within specified regions per chromosome. | per-sample |
| BEDgraph of the single-base coverage | {{ alias }}.per-base.bedgraph.gz | The single-base coverage of the genome in BED graph format. | per-sample |
| BED summary | {{ alias }}.bed_summary.tsv | Tab separated table with the average coverage and percentage of positions that are covered to a given threshold, for each region specified in the `--bed` BED file. Only generated if the BED file has at least 4 columns, where the fourth column is the region label. | per-sample |
| Coverage BED summary | {{ alias }}.coverage_bed_summary.tsv | Tab separated table with the average coverage and percentage of positions that are covered to a given threshold, for each region specified in the `--coverage_bed` BED file. Only generated if the BED file has at least 4 columns, where the fourth column is the region label. | per-sample |
| Haplocheck contamination summary | {{ alias }}.haplocheck.tsv | A table generated by [haplocheck](https://mitoverse.readthedocs.io/haplocheck/haplocheck/), with estimate of contamination from the MT genome. | per-sample |
| FAI index of the reference FASTA file | {{ ref }}.fai | FAI Index of the reference FASTA file. | aggregated |
| GZI index of the reference FASTA file | {{ ref }}.gzi | GZI Index of the reference FASTA file. | aggregated |
