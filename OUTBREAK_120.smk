import datetime
from pathlib import Path
import glob
import os, os.path
import fnmatch
print("OUTBREAK_120 v.0.2020.01.28")

DATE=str(datetime.date.today())
working_directory=os.getcwd()
base_directory=workflow.basedir + "/outbreak_120_scripts"
kraken_mini_db="/home/IDGenomics_NAS/kraken_mini_db/minikraken_20141208"

ANALYSIS_TYPE, GENUS, SPECIES= glob_wildcards('{ANALYSIS_TYPE}/{GENUS}/{SPECIES}/list_of_samples.txt')

def find_control(wildcards):
    if glob.glob(wildcards.analysis_type + "/" + wildcards.genus + "/" + wildcards.species + "/*control.gff") :
        control_gff=glob.glob(wildcards.analysis_type + "/" + wildcards.genus + "/" + wildcards.species + "/*control.gff")
        control_file=os.path.splitext(os.path.basename(str(control_gff[0])))[0]
        return(str("-o " + control_file))
    else:
        return("")

rule all:
    input:
        # abricate
        expand("{analysis_type}/{genus}/{species}/ABRICATE/abricate_presence_absence.csv", zip, analysis_type=ANALYSIS_TYPE, genus=GENUS, species=SPECIES),
        # roary
        expand("{analysis_type}/{genus}/{species}/roary.done", zip, analysis_type=ANALYSIS_TYPE, genus=GENUS, species=SPECIES),
        # iqtree
        expand("{analysis_type}/{genus}/{species}/IQTREE/{genus}.{species}.iqtree.treefile", zip, analysis_type=ANALYSIS_TYPE, genus=GENUS, species=SPECIES),
        # ggtree
        expand("{analysis_type}/{genus}/{species}/GGTREE/PLOTS_IQTREE.R", zip, analysis_type=ANALYSIS_TYPE, genus=GENUS, species=SPECIES),
        expand("{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.abricate_resistance.pdf", zip, analysis_type=ANALYSIS_TYPE, genus=GENUS, species=SPECIES),
        expand("results/{analysis_type}.{genus}.{species}.abricate_resistance.pdf", zip, analysis_type=ANALYSIS_TYPE, genus=GENUS, species=SPECIES),
#    params:
#        working_directory=working_directory,
#        base_directory=base_directory
#    threads:
#        48
#    log:
#        log="logs/all/all.log",
#        err="logs/all/all.err"
#    run:
#        # creating a table from the benchmarks
#        shell("{params.base_directory}/benchmark120_multiqc.sh {params.working_directory} 2>> {log.err} | tee -a {log.log} || true "),
#        # roary results
#        shell("{params.base_directory}/roary_multiqc.sh {params.working_directory} 2>> {log.err} | tee -a {log.log} || true "),
#        shell("{params.base_directory}/organism_multiqc.sh {params.working_directory} 2>> {log.err} | tee -a {log.log} || true "),
#        # running multiqc
#        shell("which multiqc 2>> {log.err} | tee -a {log.log}")
#        shell("multiqc --version 2>> {log.err} | tee -a {log.log}")
#        shell("cp {params.base_directory}/multiqc_config_outbreak120_snakemake.yaml multiqc_config.yaml 2>> {log.err} | tee -a {log.log} || true "),
#        shell("multiqc --outdir {params.working_directory}/logs {params.working_directory}/logs 2>> {log.err} | tee -a {log.log} || true "),

rule abricate:
    input:
        "{analysis_type}/{genus}/{species}/list_of_samples.txt",
    output:
        "{analysis_type}/{genus}/{species}/ABRICATE/abricate_presence_absence.csv"
    params:
        base_directory=base_directory,
        working_directory=working_directory,
    log:
        log="logs/abricate_summary/{analysis_type}.{genus}.{species}.log",
        err="logs/abricate_summary/{analysis_type}.{genus}.{species}.err"
    benchmark:
        "logs/benchmark/abricate_summary/{analysis_type}.{genus}.{species}.log"
    threads:
        1
    run:
        shell("which abricate 2>> {log.err} | tee -a {log.log}")
        shell("abricate --version 2>> {log.err} | tee -a {log.log}")
        shell("{params.base_directory}/abricate_organize.sh {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species} {output} {params.working_directory} 2>> {log.err} | tee -a {log.log} || true ; touch {output}")

rule roary:
    input:
        "{analysis_type}/{genus}/{species}/list_of_samples.txt",
    output:
        "{analysis_type}/{genus}/{species}/roary.done"
    log:
        log="logs/roary/{analysis_type}.{genus}.{species}.log",
        err="logs/roary/{analysis_type}.{genus}.{species}.err"
    benchmark:
        "logs/benchmark/roary/{analysis_type}.{genus}.{species}.log"
    params:
        kraken_mini_db
    threads:
        48
    run:
        shell("which roary 2>> {log.err} | tee -a {log.log}")
        shell("roary -w 2>> {log.err} | tee -a {log.log}")
        shell("if [ -d \"{wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/Roary_out\" ] ; then rm -R {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/Roary_out ; fi  2>> {log.err} | tee -a {log.log}")
        shell("roary -p {threads} -f {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/Roary_out -e -n -qc -k {params} {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/*.gff --force 2>> {log.err} | tee -a {log.log} || true ; touch {output} ")
        shell("touch {output}")

rule iqtree:
    input:
        rules.roary.output
    output:
        "{analysis_type}/{genus}/{species}/IQTREE/{genus}.{species}.iqtree.treefile",
    params:
        core_genome="{analysis_type}/{genus}/{species}/Roary_out/core_gene_alignment.aln",
        control_file=find_control
    log:
        log="logs/iqtree/{analysis_type}.{genus}.{species}.log",
        err="logs/iqtree/{analysis_type}.{genus}.{species}.err"
    benchmark:
        "logs/benchmark/iqtree/{analysis_type}.{genus}.{species}.log"
    threads:
        48
    run:
        shell("which iqtree 2>> {log.err} | tee -a {log.log}")
        shell("iqtree --version 2>> {log.err} | tee -a {log.log}")
        shell("iqtree -s {params.core_genome} -t RANDOM -m GTR+F+I -bb 1000 -alrt 1000 -pre {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/IQTREE/{wildcards.genus}.{wildcards.species}.iqtree -nt {threads} {params.control_file}  2>> {log.err} | tee -a {log.log} || true ; touch {output}")

rule ggtree_create:
    input:
        abricate_result=rules.abricate.output,
        roary_output=rules.roary.output,
        treefile=rules.iqtree.output,
    output:
        "{analysis_type}/{genus}/{species}/GGTREE/PLOTS_IQTREE.R"
    log:
        log="logs/ggtree_create/{analysis_type}.{genus}.{species}.log",
        err="logs/ggtree_create/{analysis_type}.{genus}.{species}.err"
    benchmark:
        "logs/benchmark/ggtree_create/{analysis_type}.{genus}.{species}.log"
    threads:
        1
    params:
        base_directory=base_directory,
        working_directory=working_directory,
        date=DATE,
        roary_core_genome="{analysis_type}/{genus}/{species}/Roary_out/core_gene_alignment.aln",
        roary_gene_presence="{analysis_type}/{genus}/{species}/Roary_out/gene_presence_absence.Rtab",
        nucleotide_distance="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.nucleotide_distance",
        roary_gene_presence_out="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.roary_gene_presence",
        abricate_resistance="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.abricate_resistance",
        tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.tree",
        bootstrap_tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.bootstrap_tree",
        UFboot_tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.UFboot_tree",
        distance_tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.distance_tree",
    shell:
        "{params.base_directory}/ggtree_plot_organize.sh "
        "{params.base_directory}/PLOTS_IQTREE.R "
        "{input.treefile} "
        "{params.roary_gene_presence} "
        "{params.roary_core_genome} "
        "{input.abricate_result} "
        "{params.nucleotide_distance} "
        "{params.roary_gene_presence_out} "
        "{params.abricate_resistance} "
        "{wildcards.analysis_type} "
        "{wildcards.genus} "
        "{wildcards.species} "
        "{params.date} "
        "{params.tree} "
        "{params.bootstrap_tree} "
        "{params.UFboot_tree} "
        "{params.distance_tree} "
        "{output} "
        "{params.working_directory} "
        "2>> {log.err} | tee -a {log.log}"

rule ggtree:
    input:
        rules.ggtree_create.output
    output:
        nucleotide_distance="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.nucleotide_distance.pdf",
        roary_gene_presence="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.roary_gene_presence.pdf",
        abricate_resistance="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.abricate_resistance.pdf",
        tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.tree.pdf",
        bootstrap_tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.bootstrap_tree.pdf",
        #UFboot_tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.UFboot_tree.pdf",
        #distance_tree="{analysis_type}/{genus}/{species}/GGTREE/{analysis_type}.{genus}.{species}.distance_tree.pdf",
    log:
        log="logs/ggtree/{analysis_type}.{genus}.{species}.log",
        err="logs/ggtree/{analysis_type}.{genus}.{species}.err"
    benchmark:
        "logs/benchmark/ggtree/{analysis_type}.{genus}.{species}.log"
    threads:
        1
    shell:
        "Rscript {input} 2>> {log.err} | tee -a {log.log} || true ; touch {output}"

rule ggtree_move:
    input:
        rules.ggtree.output.nucleotide_distance,
        rules.ggtree.output.roary_gene_presence,
        rules.ggtree.output.abricate_resistance,
    output:
        pdf_dist="results/{analysis_type}.{genus}.{species}.nucleotide_distance.pdf",
        pdf_gene="results/{analysis_type}.{genus}.{species}.roary_gene_presence.pdf",
        pdf_abri="results/{analysis_type}.{genus}.{species}.abricate_resistance.pdf",
        jpg_dist="logs/results/{analysis_type}.{genus}.{species}.nucleotide_distance_mqc.jpg",
        jpg_gene="logs/results/{analysis_type}.{genus}.{species}.roary_gene_presence_mqc.jpg",
        jpg_abri="logs/results/{analysis_type}.{genus}.{species}.abricate_resistance_mqc.jpg",
    log:
        log="logs/ggtree_move/{analysis_type}.{genus}.{species}.log",
        err="logs/ggtree_move/{analysis_type}.{genus}.{species}.err"
    benchmark:
        "logs/benchmark/ggtree_move/{analysis_type}.{genus}.{species}.log"
    threads:
        1
    run:
        shell("cp {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/GGTREE/*pdf results/. 2>> {log.err} | tee -a {log.log} || true ; touch {output.pdf_dist} {output.pdf_gene} {output.pdf_abri}")
        shell("cp {wildcards.analysis_type}/{wildcards.genus}/{wildcards.species}/GGTREE/*_mqc.jpg logs/results/. 2>> {log.err} | tee -a {log.log} || true ; touch {output.jpg_dist} {output.jpg_gene} {output.jpg_abri}")
