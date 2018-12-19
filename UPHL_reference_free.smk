import fnmatch
import os
import glob
import shutil
from os.path import join

base_directory=workflow.basedir
output_directory=os.getcwd()
seqyclean_adaptors="/home/Bioinformatics/Data/SeqyClean_data/PhiX_174_plus_Adapters.fasta"
mash_sketches="/home/Bioinformatics/Data/RefSeqSketchesDefaults.msh"

SAMPLE, MIDDLE, EXTENSION = glob_wildcards('Sequencing_reads/Raw/{sample, [^_]+}_{middle}.f{extension}')
DATABASE = ['argannot', 'resfinder', 'card', 'plasmidfinder', 'vfdb', 'ecoli_vf', 'ncbi', 'ecoh', 'serotypefinder']

rule all:
    input:
    # copying files over
        expand("Sequencing_reads/Raw/{sample}_{middle}.f{extension}", zip, sample=SAMPLE, middle=MIDDLE, extension=EXTENSION),
        # running seqyclean
        expand("Sequencing_reads/QCed/{sample}_clean_PE1.fastq", sample=SAMPLE),
        expand("Sequencing_reads/QCed/{sample}_clean_PE2.fastq", sample=SAMPLE),
        "Sequencing_reads/Logs/seqyclean_summary.txt",
        # running FastQC
        expand("fastqc/{sample}_clean_{end}_fastqc.zip", sample=SAMPLE, end=['PE1', 'PE2', 'SE']),
        # running shovill
        expand("ALL_assembled/{sample}_contigs.fa",sample=SAMPLE),
        # mash results
        expand("mash/{sample}.clean_all.fastq.msh.distance.sorted.txt", sample=SAMPLE),
        "mash/mash_results.txt",
        # prokka results
        expand("ALL_gff/{sample}.gff", sample=SAMPLE),
        # quast results
        expand("quast/{sample}.report.txt", sample=SAMPLE),
        # seqsero results
        expand("SeqSero/{sample}.Seqsero_result.txt", sample=SAMPLE),
        "SeqSero/Seqsero_serotype_results.txt",
        # cg-pipeline results
        expand("cg-pipeline/{sample}.{raw_or_clean}.out.txt", sample=SAMPLE,raw_or_clean=['raw', 'clean']),
        "cg-pipeline/cg-pipeline-summary.txt",
        # abricate results
        expand("abricate_results/{database}/{database}.{sample}.out.tab", sample=SAMPLE, database=DATABASE),
        expand("abricate_results/{database}/{database}.summary.csv", database=DATABASE)
    params:
        output_directory=output_directory,
        base_directory=workflow.basedir
    threads:
        48
    run:
        # running fastqc
        shell("mkdir -p fastqc")
        shell("fastqc --outdir fastqc --threads {threads} Sequencing_reads/Raw/*.f*"),
        # creating a table from the benchmarks
        shell("{params.base_directory}/benchmark_multiqc.sh {params.output_directory}"),
        # getting the Summary
        shell("{params.base_directory}/check_multiqc.sh {params.output_directory}"),
        # running multiqc
        shell("cp {params.base_directory}/multiqc_config_URF_snakemake.yaml multiqc_config.yaml"),
        shell("multiqc --outdir {params.output_directory}/logs --cl_config \"prokka_fn_snames: True\" {params.output_directory}"),

def get_read1(wildcards):
    read1=glob.glob("Sequencing_reads/Raw/" + wildcards.sample + "*_R1_001.fastq.gz") + glob.glob("Sequencing_reads/Raw/" + wildcards.sample + "_1.fastq")
    return(''.join(read1))

def get_read2(wildcards):
    read2=glob.glob("Sequencing_reads/Raw/" + wildcards.sample + "*_R2_001.fastq.gz") + glob.glob("Sequencing_reads/Raw/" + wildcards.sample + "_2.fastq")
    return(''.join(read2))

rule seqyclean:
    input:
        read1= get_read1,
        read2= get_read2
    output:
        "Sequencing_reads/QCed/{sample}_clean_PE1.fastq",
        "Sequencing_reads/QCed/{sample}_clean_PE2.fastq",
        "Sequencing_reads/QCed/{sample}_clean_SE.fastq",
        "Sequencing_reads/Logs/{sample}_clean_SummaryStatistics.txt",
        "Sequencing_reads/Logs/{sample}_clean_SummaryStatistics.tsv"
    params:
        seqyclean_adaptors
    threads:
        1
    log:
        "logs/seqyclean/{sample}.log"
    benchmark:
        "logs/benchmark/seqyclean/{sample}.log"
    run:
        shell("seqyclean -minlen 25 -qual -c {params} -1 {input.read1} -2 {input.read2} -o Sequencing_reads/QCed/{wildcards.sample}_clean")
        shell("mv Sequencing_reads/QCed/{wildcards.sample}_clean_SummaryStatistics* Sequencing_reads/Logs/.")

rule seqyclean_multiqc:
    input:
        expand("Sequencing_reads/Logs/{sample}_clean_SummaryStatistics.tsv", sample=SAMPLE)
    output:
        "Sequencing_reads/Logs/seqyclean_summary.txt"
    log:
        "logs/seqyclean_multiqc/log.log"
    benchmark:
        "logs/benchmark/seqyclean_multiqc/benchmark.log"
    threads:
        1
    params:
        base_directory= workflow.basedir,
        output_directory= output_directory
    shell:
        "{params.base_directory}/seqyclean_multiqc.sh {params.output_directory}"

rule fastqc:
    input:
        "Sequencing_reads/QCed/{sample}_clean_{end}.fastq"
    output:
        "fastqc/{sample}_clean_{end}_fastqc.zip",
        "fastqc/{sample}_clean_{end}_fastqc.html"
    threads:
        1
    shell:
        "fastqc --outdir fastqc --threads {threads} {input}"

rule shovill:
    input:
        read1="Sequencing_reads/QCed/{sample}_clean_PE1.fastq",
        read2="Sequencing_reads/QCed/{sample}_clean_PE2.fastq"
    threads:
        48
    log:
        "logs/shovill/{sample}.log"
    benchmark:
        "logs/benchmark/shovill/{sample}.log"
    output:
        "shovill_result/{sample}/contigs.fa",
        "shovill_result/{sample}/contigs.gfa",
        "shovill_result/{sample}/shovill.corrections",
        "shovill_result/{sample}/shovill.log",
        "shovill_result/{sample}/spades.fasta"
    shell:
        "shovill --cpu {threads} --ram 200 --outdir shovill_result/{wildcards.sample} --R1 {input.read1} --R2 {input.read2} --force"

rule shovill_move:
    input:
        "shovill_result/{sample}/contigs.fa"
    log:
        "logs/shovill_move/{sample}.log"
    benchmark:
        "logs/benchmark/shovill_move/{sample}.log"
    threads:
        1
    output:
        "ALL_assembled/{sample}_contigs.fa"
    shell:
        "cp {input} {output}"

rule mash_cat:
    input:
        "Sequencing_reads/QCed/{sample}_clean_PE1.fastq",
        "Sequencing_reads/QCed/{sample}_clean_PE2.fastq",
        "Sequencing_reads/QCed/{sample}_clean_SE.fastq"
    output:
        "mash/{sample}.clean_all.fastq"
    log:
        "logs/mash_cat/{sample}.log"
    benchmark:
        "logs/benchmark/mash_cat/{sample}.log"
    threads:
        1
    shell:
        "cat {input} > {output}"

rule mash_sketch:
    input:
        rules.mash_cat.output
    output:
        "mash/{sample}.clean_all.fastq.msh"
    log:
        "logs/mash_sketch/{sample}.log"
    benchmark:
        "logs/benchmark/mash_sketch/{sample}.log"
    threads:
        1
    shell:
        "mash sketch -m 2 -p {threads} {input}"

rule mash_dist:
    input:
        rules.mash_sketch.output
    output:
        "mash/{sample}.clean_all.fastq.msh.distance.txt"
    threads:
        48
    params:
        mash_sketches
    log:
        "logs/mash_dist/{sample}.log"
    benchmark:
        "logs/benchmark/mash_dist/{sample}.log"
    shell:
        "mash dist -p {threads} {params} {input} > {output}"

rule mash_sort:
    input:
        rules.mash_dist.output
    output:
        "mash/{sample}.clean_all.fastq.msh.distance.sorted.txt"
    log:
        "logs/mash_sort/{sample}.log"
    benchmark:
        "logs/benchmark/mash_sort/{sample}.log"
    threads:
        1
    shell:
        "sort -gk3 {input} > {output} "

rule mash_multiqc:
    input:
        expand("mash/{sample}.clean_all.fastq.msh.distance.sorted.txt", sample=SAMPLE)
    output:
        "mash/mash_results.txt"
    log:
        "logs/mash_pipeline_multiqc/log.log"
    benchmark:
        "logs/benchmark/mash_pipeline_multiqc/benchmark.log"
    threads:
        1
    params:
        base_directory= workflow.basedir,
        output_directory= output_directory
    shell:
        "{params.base_directory}/mash_multiqc.sh {params.output_directory}"

rule prokka:
    input:
        contig_file="ALL_assembled/{sample}_contigs.fa",
        mash_file="mash/{sample}.clean_all.fastq.msh.distance.sorted.txt"
    threads:
        48
    output:
        "Prokka/{sample}/{sample}.err",
        "Prokka/{sample}/{sample}.fna",
        "Prokka/{sample}/{sample}.gff",
        "Prokka/{sample}/{sample}.tbl",
        "Prokka/{sample}/{sample}.faa",
        "Prokka/{sample}/{sample}.fsa",
        "Prokka/{sample}/{sample}.log",
        "Prokka/{sample}/{sample}.tsv",
        "Prokka/{sample}/{sample}.ffn",
        "Prokka/{sample}/{sample}.gbk",
        "Prokka/{sample}/{sample}.sqn",
        "Prokka/{sample}/{sample}.txt"
    log:
        "logs/prokka/{sample}.log"
    benchmark:
        "logs/benchmark/prokka/{sample}.log"
    threads:
        1
    shell:
    	"mash_genus=($(head -n 1 {input.mash_file} | cut -f 1 | awk -F \"-.-\" '{{ print $NF }}' | sed 's/.fna//g' | awk -F \"_\" '{{ print $1 }}' )) ; "
        "mash_spces=($(head -n 1 {input.mash_file} | cut -f 1 | awk -F \"-.-\" '{{ print $NF }}' | sed 's/.fna//g' | awk -F \"_\" '{{ print $2 }}' )) ; "
        "prokka --cpu {threads} --compliant --centre --UPHL --mincontiglen 500 --outdir Prokka/{wildcards.sample} --locustag locus_tag --prefix {wildcards.sample} --genus $mash_genus --species $mash_spces --force {input.contig_file}"

rule prokka_move:
    input:
        "Prokka/{sample}/{sample}.gff"
    output:
        "ALL_gff/{sample}.gff"
    log:
        "logs/prokka_move/{sample}.log"
    benchmark:
        "logs/benchmark/prokka_move/{sample}.log"
    threads:
        1
    shell:
        "cp {input} {output}"

rule quast:
    input:
        "ALL_assembled/{sample}_contigs.fa"
    output:
        "quast/{sample}/report.html",
        "quast/{sample}/report.tsv",
        "quast/{sample}/transposed_report.tex",
        "quast/{sample}/transposed_report.txt",
        "quast/{sample}/icarus.html",
        "quast/{sample}/quast.log",
        "quast/{sample}/report.tex",
        "quast/{sample}/report.txt",
        "quast/{sample}/transposed_report.tsv"
    log:
        "logs/quast/{sample}.log"
    benchmark:
        "logs/benchmark/quast/{sample}.log"
    threads:
        1
    shell:
      "quast {input} --output-dir quast/{wildcards.sample}"

rule quast_move:
    input:
        "quast/{sample}/report.txt"
    output:
        "quast/{sample}.report.txt"
    log:
        "logs/quast_move/{sample}.log"
    benchmark:
        "logs/benchmark/quast_move/{sample}.log"
    threads:
        1
    shell:
        "cp {input} {output}"

rule GC_pipeline_shuffle_raw:
    input:
        read1= get_read1,
        read2= get_read2
    output:
        "Sequencing_reads/shuffled/{sample}_raw_shuffled.fastq.gz"
    log:
        "logs/gc_pipeline_shuffle_raw/{sample}.log"
    benchmark:
        "logs/benchmark/gc_pipeline_shuffle_raw/{sample}.log"
    threads:
        1
    shell:
        "run_assembly_shuffleReads.pl -gz {input.read1} {input.read2} > {output}"

rule GC_pipeline_shuffle_clean:
    input:
        read1="Sequencing_reads/QCed/{sample}_clean_PE1.fastq",
        read2="Sequencing_reads/QCed/{sample}_clean_PE2.fastq"
    output:
        "Sequencing_reads/shuffled/{sample}_clean_shuffled.fastq.gz"
    log:
        "logs/gc_pipeline_shuffle_clean/{sample}.log"
    benchmark:
        "logs/benchmark/gc_pipeline_shuffle_clean/{sample}.log"
    threads:
        1
    shell:
        "run_assembly_shuffleReads.pl -gz {input.read1} {input.read2} > {output}"

rule GC_pipeline:
    input:
        shuffled_fastq="Sequencing_reads/shuffled/{sample}_{raw_or_clean}_shuffled.fastq.gz",
        quast_file="quast/{sample}.report.txt"
    output:
        "cg-pipeline/{sample}.{raw_or_clean}.out.txt"
    threads:
        48
    log:
        "logs/gc_pipeline/{sample}.{raw_or_clean}.log"
    benchmark:
        "logs/benchmark/gc_pipeline/{sample}.{raw_or_clean}.log"
    params:
        base_directory=workflow.basedir
    run:
        if "PNUSAS" in wildcards.sample:
            shell("run_assembly_readMetrics.pl {input.shuffled_fastq} --fast --numcpus {threads} -e 5000000 > {output}")
        elif "PNUSAE" in wildcards.sample:
            shell("run_assembly_readMetrics.pl {input.shuffled_fastq} --fast --numcpus {threads} -e 5000000 > {output}")
        elif "PNUSAC" in wildcards.sample :
            shell("run_assembly_readMetrics.pl {input.shuffled_fastq} --fast --numcpus {threads} -e 1600000 > {output}")
        elif "PNUSAL" in wildcards.sample:
            shell("run_assembly_readMetrics.pl {input.shuffled_fastq} --fast --numcpus {threads} -e 3000000 > {output}")
        else:
            shell("{params.base_directory}/genome_length_cg.sh {input.shuffled_fastq} {input.quast_file} {threads} {output}")

rule GC_pipeline_multiqc:
    input:
        expand("cg-pipeline/{sample}.{raw_or_clean}.out.txt", sample=SAMPLE, raw_or_clean=['raw', 'clean'])
    output:
        "cg-pipeline/cg-pipeline-summary.txt"
    log:
        "logs/gc_pipeline_multiqc/log.log"
    benchmark:
        "logs/benchmark/gc_pipeline_multiqc/benchmark.log"
    threads:
        1
    params:
        base_directory=workflow.basedir,
        output_directory=output_directory
    shell:
        "{params.base_directory}/cgpipeline_multiqc.sh {params.output_directory}"

rule seqsero:
    input:
        "Sequencing_reads/QCed/{sample}_clean_PE1.fastq",
        "Sequencing_reads/QCed/{sample}_clean_PE2.fastq"
    output:
        "SeqSero/{sample}/Seqsero_result.txt",
        "SeqSero/{sample}/data_log.txt"
    log:
        "logs/seqsero/{sample}.log"
    benchmark:
        "logs/benchmark/seqsero/{sample}.log"
    threads:
        1
    shell:
        "SeqSero.py -m 2 -d SeqSero/{wildcards.sample} -i {input}"

rule seqsero_move:
    input:
        "SeqSero/{sample}/Seqsero_result.txt"
    output:
        "SeqSero/{sample}.Seqsero_result.txt"
    log:
        "logs/seqsero_move/{sample}.log"
    benchmark:
        "logs/benchmark/seqsero_move/{sample}.log"
    threads:
        1
    shell:
        "cp {input} {output}"

rule seqsero_multiqc:
    input:
        expand("SeqSero/{sample}.Seqsero_result.txt", sample=SAMPLE)
    output:
        "SeqSero/Seqsero_serotype_results.txt"
    log:
        "logs/seqsero_multiqc/log.log"
    benchmark:
        "logs/benchmark/seqsero_multiqc/benchmark.log"
    params:
        base_directory=workflow.basedir,
        output_directory=output_directory
    threads:
        1
    shell:
        "{params.base_directory}/seqsero_multiqc.sh {params.output_directory}"

rule abricate:
    input:
        "ALL_assembled/{sample}_contigs.fa"
    output:
        "abricate_results/{database}/{database}.{sample}.out.tab"
    log:
        "logs/abricate/{sample}.{database}.log"
    benchmark:
        "logs/benchmark/abricate_{database}/{sample}.log"
    threads:
        1
    shell:
        "abricate -db {wildcards.database} {input} > {output}"

rule abricate_combine:
    input:
        expand("abricate_results/{database}/{database}.{sample}.out.tab", sample=SAMPLE, database=DATABASE)
    output:
        "abricate_results/{database}/{database}.summary.txt"
    log:
        "logs/abricate_combine_{database}/{database}.log"
    benchmark:
        "logs/benchmark/abricate_combine/{database}.log"
    threads:
        1
    shell:
        "abricate --summary abricate_results/{wildcards.database}/{wildcards.database}*tab > {output}"

rule abricate_multiqc:
    input:
        "abricate_results/{database}/{database}.summary.txt"
    output:
        "abricate_results/{database}/{database}.summary.csv"
    log:
        "logs/abricate_multiqc/{database}.log"
    benchmark:
        "logs/benchmark/abricate_multiqc/{database}.log"
    threads:
        1
    shell:
        "cat {input} | "
        "sed 's/#//g' | sed 's/.tab//g' | sed \"s/{wildcards.database}.//g\" | "
        "awk '{{ sub(\"^.*/\", \"\", $1); print}}' | "
        "awk '{{ for (i=1;i<=NF;i++) if ($i ~ \";\" )gsub(\";.*$\",\"\",$i)g ; else continue}}{{print $0}}' | "
        "awk '{{ $2=\"\" ; print $0 }}' | sed 's/\t/,/g' | sed 's/ /,/g' | "
        "sed 's/[.],/0,/g' | sed 's/,[.]/,0/g' | sed 's/,,/,/g' "
        "> {output}"
