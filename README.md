# Transform raw sequencing files (.fastq / .fastq.gz) into a cleaned, aligned, deduplicated BAM and a gene-level counts matrix

## Inputs
 - raw FASTQ(s) (single or paired)
 - genome FASTA (`genome.fa`)
 - annotation GTF (`genes.gtf`)
 - barcode/UMI file (if applicable)

## Outputs (per sample)
 - trimmed FASTQ(s)
 - aligned, coordinate-sorted BAM (deduplicated or UMI-deduped)
 - gene-level counts (from `featureCounts`)
 - QC logs and metrics

## Minimal step-by-step pipeline

<br/>

### 1) Prepare reference

🔶 &nbsp; Build STAR index (adjust `--sjdbOverhang` = readLength-1):

Inputs:
 - `/path/to/genome.fa` (genome FASTA)
 - `/path/to/genes.gtf` (annotation GTF)

Output:
 - `/path/to/STAR_index/` directory (STAR index files)

```bash
STAR --runThreadN 16 --runMode genomeGenerate --genomeDir /path/to/STAR_index \
     --genomeFastaFiles /path/to/genome.fa --sjdbGTFfile /path/to/genes.gtf \
     --sjdbOverhang 100
```

<br/>

### 2) Adapter and quality trimming (Trimmomatic)

🔶 &nbsp; Paired-end example:

Inputs:
 - `R1.fastq.gz`, `R2.fastq.gz` (raw paired FASTQ files)
 - `adapters.fa` (adapter sequence file used by ILLUMINACLIP)

Outputs:
 - `R1.trim.PE.fastq.gz`, `R2.trim.PE.fastq.gz` (paired reads kept)
 - `R1.trim.SE.fastq.gz`, `R2.trim.SE.fastq.gz` (orphaned single reads)

```bash
java -jar trimmomatic.jar PE -threads 8 R1.fastq.gz R2.fastq.gz \
  R1.trim.PE.fastq.gz R1.trim.SE.fastq.gz R2.trim.PE.fastq.gz R2.trim.SE.fastq.gz \
  ILLUMINACLIP:adapters.fa:2:30:10 SLIDINGWINDOW:4:15 MINLEN:36
```

<br/>

🔶 &nbsp; Single-end example:

Inputs:
 - `sample.fastq.gz` (raw single-end FASTQ)
 - `adapters.fa` (adapter sequence file)

Output:
 - `sample.trim.fastq.gz` (trimmed single-end FASTQ)

```bash
java -jar trimmomatic.jar SE -threads 8 sample.fastq.gz sample.trim.fastq.gz \
  ILLUMINACLIP:adapters.fa:2:30:10 SLIDINGWINDOW:4:15 MINLEN:36
```

Expected outputs:
    - Paired: `R1.trim.PE.fastq.gz`, `R2.trim.PE.fastq.gz` (kept pairs) and `R1.trim.SE.fastq.gz`, `R2.trim.SE.fastq.gz` (orphaned reads)
    - Single: `sample.trim.fastq.gz`

<br>

### 3) Demultiplex / extract barcodes and UMIs (bantools)

🔶 &nbsp; Use `bantools` to split by sample barcodes and add UMI tags (e.g., `CB`, `UB`) to reads.

Inputs:
 - `R1.trim.PE.fastq.gz`, `R2.trim.PE.fastq.gz` (trimmed FASTQs)
 - `barcodes.tsv` (table mapping barcodes to sample IDs)

Outputs:
 - `demux/<sample>_R1.fastq.gz`, `demux/<sample>_R2.fastq.gz` (per-sample FASTQs), or
 - `demux/<sample>.tagged.bam` (if bantools writes a tagged BAM)

```bash
bantools demultiplex --barcodes barcodes.tsv \
  --inR1 R1.trim.PE.fastq.gz --inR2 R2.trim.PE.fastq.gz \
  --outdir demux/ --umi --umi-tag UB --cell-tag CB
```

Example outputs: `demux/sample1_R1.fastq.gz`, `demux/sample1_R2.fastq.gz`, or `demux/sample1.tagged.bam`

<br>

### 4) Align reads with STAR (2-pass recommended for RNA-seq)

🔶 &nbsp; Run STAR with `--twopassMode Basic` and output sorted BAM:

Inputs:
 - `/path/to/STAR_index/` (STAR index directory)
 - `R1.trim.PE.fastq.gz`, `R2.trim.PE.fastq.gz` (trimmed, gzipped FASTQs)

Outputs:
 - `sample.Aligned.sortedByCoord.out.bam` (coordinate-sorted BAM)
 - `sample.Log.final.out` (STAR alignment summary)

```bash
STAR --runThreadN 16 --genomeDir /path/to/STAR_index \
  --readFilesCommand zcat --readFilesIn R1.trim.PE.fastq.gz R2.trim.PE.fastq.gz \
  --twopassMode Basic --outSAMtype BAM SortedByCoordinate --outFileNamePrefix sample.
```

🔶 &nbsp; Two explicit-pass example (if you prefer manual):

Inputs:
 - `R1.trim.PE.fastq.gz`, `R2.trim.PE.fastq.gz` (trimmed FASTQs)

Outputs:
 - `sample.pass1.SJ.out.tab` (per-sample SJ from pass1)

```bash
# pass1
STAR --runThreadN 16 --genomeDir /path/to/STAR_index \
  --readFilesCommand zcat --readFilesIn R1.trim.PE.fastq.gz R2.trim.PE.fastq.gz \
  --outFileNamePrefix sample.pass1.
# gather SJ.out.tab files across samples, then re-run STAR with sjdbFileChrStartEnd
```

Inputs:
 - `merged_SJ.out.tab` (merged splice junctions file) plus trimmed FASTQs
 
Outputs:
 - `sample.Aligned.sortedByCoord.out.bam` (final sorted BAM from pass2)
 - STAR logs

```bash
# pass2
STAR --runThreadN 16 --genomeDir /path/to/STAR_index \
  --readFilesCommand zcat --readFilesIn R1.trim.PE.fastq.gz R2.trim.PE.fastq.gz \
  --sjdbFileChrStartEnd merged_SJ.out.tab --outSAMtype BAM SortedByCoordinate \
  --outFileNamePrefix sample.
```

Expected outputs: `sample.Aligned.sortedByCoord.out.bam`, `sample.Log.final.out`

<br>

### 5) Add read groups and mark duplicates (Picard) — or do UMI-aware deduplication if UMIs present

🔶 &nbsp; Add read groups:

Inputs:
 - `sample.bam` (BAM produced by STAR)

Outputs:
 - `sample.rg.bam` (BAM with read group tags added). The RG fields are metadata for downstream tools.

```bash
java -jar picard.jar AddOrReplaceReadGroups I=sample.bam O=sample.rg.bam \
  RGID=ID RGLB=lib RGPL=ILLUMINA RGPU=unit RGSM=sample
```

<br>

🔶 &nbsp; Mark duplicates (if no UMIs):

Inputs:
 - `sample.rg.bam` (BAM with read groups)

Outputs:
 - `sample.dedup.bam` (duplicates marked/removed)
 - `sample.metrics.txt` (duplication metrics)
 - `sample.dedup.bam.bai` (index, created when `CREATE_INDEX=true`)

```bash
java -jar picard.jar MarkDuplicates I=sample.rg.bam O=sample.dedup.bam \
  M=sample.metrics.txt CREATE_INDEX=true
```
<br>

🔶 &nbsp; If UMIs exist, use a UMI-aware tool (for example, UMI-tools) instead of Picard MarkDuplicates.

Inputs (UMI-tools extract):
 - `R1.trim.fastq.gz`, `R2.trim.fastq.gz` (trimmed FASTQs)

Outputs (UMI-tools extract):
 - `R1.extracted.fastq.gz`, `R2.extracted.fastq.gz` (UMI-extracted FASTQs)


```bash
# UMI-tools example (after alignment; assumes UMI in `UB` tag or in read name)
# extract UMIs to tags (if needed) and sort by name
umi_tools extract --bc-pattern=NNNNNNNN --stdin=R1.trim.fastq.gz --stdout=R1.extracted.fastq.gz \
  --read2-in=R2.trim.fastq.gz --read2-out=R2.extracted.fastq.gz
# align (STAR), then deduplicate using tags (example tag: UB)
```

Inputs (UMI-tools dedup):
 - `sample.Aligned.sortedByCoord.out.bam` (aligned BAM)

Outputs (UMI-tools dedup):
 - `sample.umi_dedup.bam` (UMI-deduped BAM)

```bash
umi_tools dedup -I sample.Aligned.sortedByCoord.out.bam -S sample.umi_dedup.bam --umi-tag=UB
```

Expected outputs: `sample.dedup.bam` or `sample.umi_dedup.bam` plus metrics files like `sample.metrics.txt` and index `.bai`

<br>

### 6) Quantify features (subread `featureCounts`)

🔶 &nbsp; Gene-level counts (paired and strandedness flags as appropriate):

Inputs:
 - `/path/to/genes.gtf` (annotation GTF)
 - `sample.dedup.bam` (deduplicated or UMI-deduped BAM)

Output:
 - `sample.featureCounts.txt` (counts table for that sample)

   - Options examples:
     - Paired-end: add `-p`
     - Stranded: `-s 0` (unstranded), `-s 1` (stranded), `-s 2` (reverse)
     - Gene id attribute: `-t exon -g gene_id`
   - Example full command (paired, reverse stranded):

```bash
featureCounts -T 8 -a /path/to/genes.gtf -o sample.featureCounts.txt sample.dedup.bam
```

Inputs (batch featureCounts):
 - `genes.gtf` (annotation GTF)
 - multiple dedup BAMs (`sample1.dedup.bam`, `sample2.dedup.bam`, ...)

Output:
 - `all_samples.counts.txt` (matrix-like file: genes x samples)

```bash
featureCounts -T 8 -p -s 2 -t exon -g gene_id -a genes.gtf -o all_samples.counts.txt \
  sample1.dedup.bam sample2.dedup.bam
```

<br>

Output: `all_samples.counts.txt` (matrix-like file with counts per gene per sample)

<br>

### 7) Collect QC and aggregate reports

🔶 &nbsp; Use STAR `Log.final.out` and Picard metrics for mapping/duplication rates.

```bash
multiqc . -o qc_report/
```

Inputs:
 - directory with log files from STAR, Picard, featureCounts, etc.

Output:
 - `qc_report/` directory containing `multiqc_report.html` and aggregated data

🔸Optionally run `multiqc` to aggregate logs into one report.

```bash
multiqc . -o qc_report/
```

## Notes & edge cases (short)
- Single-end vs paired-end: use the corresponding Trimmomatic and STAR input modes.
- UMIs: perform UMI-aware deduplication (UMI-tools or similar). Picard MarkDuplicates is not UMI-aware.
- Strandedness: set the correct `-s` option in `featureCounts` (0/1/2) to avoid wrong counts.
- Resources: STAR index and alignment can require large RAM for big genomes (human ~30–60+ GB depending on settings).
