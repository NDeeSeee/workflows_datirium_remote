cwlVersion: v1.0
class: Workflow


requirements:
  - class: StepInputExpressionRequirement
  - class: InlineJavascriptRequirement
  - class: MultipleInputFeatureRequirement


'sd:upstream':
  chipseq_sample:
    - "chipseq-se.cwl"
    - "chipseq-pe.cwl"
    - "trim-chipseq-pe.cwl"
    - "trim-chipseq-se.cwl"
  chipseq_control:
    - "chipseq-se.cwl"
    - "chipseq-pe.cwl"
    - "trim-chipseq-pe.cwl"
    - "trim-chipseq-se.cwl"

    
inputs:

  alias:
    type: string
    label: "Experiment short name/Alias"
    sd:preview:
      position: 1

  islands_file:
    type: File
    label: "XLS called peaks file"
    'sd:upstreamSource': "chipseq_sample/macs2_called_peaks"
    'sd:localLabel': true
    format: "http://edamontology.org/format_3468"
    doc: "Input XLS file generated by MACS2"

  islands_control_file:
    type: File?
    'sd:upstreamSource': "chipseq_control/macs2_called_peaks"
    'sd:localLabel': true
    label: "XLS called peaks file (control)"
    format: "http://edamontology.org/format_3468"
    doc: "Control XLS file generated by MACS2"

  bambai_pair:
    type: File
    'sd:upstreamSource': "chipseq_sample/bambai_pair"
    secondaryFiles:
    - .bai
    label: "Coordinate sorted BAM+BAI files"
    format: "http://edamontology.org/format_2572"
    doc: "Coordinate sorted BAM file and BAI index file"

  annotation_file:
    type: File
    label: "TSV annotation file"
    format: "http://edamontology.org/format_3475"
    doc: "TSV annotation file"

  chrom_length_file:
    type: File
    label: "Chromosome length file"
    format: "http://edamontology.org/format_2330"
    doc: "Chromosome length file"

  stitch_distance:
    type: int?
    default: 20000
    label: "Stitching distance"
    doc: "Linking distance for stitching"
    'sd:layout':
      advanced: true

  tss_distance:
    type: int?
    default: 2500
    label: "TSS distance"
    doc: "Distance from TSS to exclude, 0 = no TSS exclusion"
    'sd:layout':
      advanced: true

  promoter_bp:
    type: int?
    default: 1000
    label: "Promoter distance"
    doc: "Promoter distance for gene names assignment"
    'sd:layout':
      advanced: true

outputs:

  png_file:
    type: File
    label: "ROSE visualization plot"
    format: "http://edamontology.org/format_3603"
    doc: "Generated by ROSE visualization plot"
    outputSource: rename_png/target_file

  gene_names_file:
    type: File
    label: "Gateway Super Enhancer + gene names"
    format: "http://edamontology.org/format_3475"
    doc: "Gateway Super Enhancer results from ROSE with assigned gene names"
    outputSource: add_island_names/output_file

  bigbed_file:
    type: File
    label: "Gateway Super Enhancer bigBed file"
    format: "http://edamontology.org/format_3475"
    doc: "Gateway Super Enhancer bigBed file"
    outputSource: bed_to_bigbed/bigbed_file


steps:

  make_gff:
    run: ../tools/makegff.cwl
    in:
      islands_file: islands_file
      islands_control_file: islands_control_file
    out: [gff_file]

  run_rose:
    run: ../tools/rose.cwl
    in:
      binding_sites_file: make_gff/gff_file
      bam_file: bambai_pair
      annotation_file: annotation_file
      stitch_distance: stitch_distance
      tss_distance: tss_distance
    out: [plot_points_pic, gateway_super_enhancers_bed]

  rename_png:
    in:
      source_file: run_rose/plot_points_pic
      target_filename:
        source: bambai_pair
        valueFrom: $(self.location.split('/').slice(-1)[0].split('.').slice(0,-1).join('.')+"_default_s_enhcr.png")
    out: [target_file]
    run:
      cwlVersion: v1.0
      class: CommandLineTool
      requirements:
      - class: DockerRequirement
        dockerPull: biowardrobe2/scidap:v0.0.3
      inputs:
        source_file:
          type: File
          inputBinding:
            position: 5
          doc: source file to rename
        target_filename:
          type: string
          inputBinding:
            position: 6
          doc: filename to rename to
      outputs:
        target_file:
          type: File
          outputBinding:
            glob: "*"
      baseCommand: ["cp"]
      doc: Tool renames (copy) `source_file` to `target_filename`

  sort_bed:
    run: ../tools/linux-sort.cwl
    in:
      unsorted_file: run_rose/gateway_super_enhancers_bed
      key:
        default: ["1,1","2,2n","3,3n"]
    out: [sorted_file]

  reduce_bed:
    in:
      input_file: sort_bed/sorted_file
    out: [output_file]
    run:
      cwlVersion: v1.0
      class: CommandLineTool
      requirements:
      - class: DockerRequirement
        dockerPull: biowardrobe2/scidap:v0.0.3
      inputs:
        input_file:
          type: File
          inputBinding:
            position: 5
          doc: Input BED6 file to be reduced to BED4
      outputs:
        output_file:
          type: File
          outputBinding:
            glob: "*"
      baseCommand: [bash, '-c']
      arguments:
      - cat $0 | cut -f 1-4 > `basename $0`
      doc: Tool converts BED6 to BED4 by reducing column numbers

  bed_to_bigbed:
    in:
      input_bed: reduce_bed/output_file
      chrom_length_file: chrom_length_file
      bed_type:
        default: "bed4"
      output_filename:
        source: bambai_pair
        valueFrom: $(self.location.split('/').slice(-1)[0].split('.').slice(0,-1).join('.')+"_default_s_enhcr.bb")
    out: [bigbed_file]
    run:
      cwlVersion: v1.0
      class: CommandLineTool
      requirements:
      - class: DockerRequirement
        dockerPull: biowardrobe2/ucscuserapps:v358
      inputs:
        bed_type:
          type: string
          inputBinding:
            position: 5
            prefix: -type=
            separate: false
          doc: Type of BED file in a form of bedN[+[P]]. By default bed3 to three required BED fields
        input_bed:
          type: File
          inputBinding:
            position: 6
          doc: Input BED file
        chrom_length_file:
          type: File
          inputBinding:
            position: 7
          doc: Chromosome length files
        output_filename:
          type: string
          inputBinding:
            position: 8
          doc: Output filename
      outputs:
        bigbed_file:
          type: File
          outputBinding:
            glob: "*"
      baseCommand: ["bedToBigBed"]
      doc: Tool converts bed to bigBed

  bed_to_macs:
    in:
      input_file: sort_bed/sorted_file
    out: [output_file]
    run:
      cwlVersion: v1.0
      class: CommandLineTool
      requirements:
      - class: DockerRequirement
        dockerPull: biowardrobe2/scidap:v0.0.3
      inputs:
        input_file:
          type: File
          inputBinding:
            position: 5
          doc: Input file to be converted to MACS2 output format
      outputs:
        output_file:
          type: File
          outputBinding:
            glob: "*"
      baseCommand: [bash, '-c']
      arguments:
      - cat $0 | grep -v "#" | awk
        'BEGIN {print "chr\tstart\tend\tlength\tabs_summit\tpileup\t-log10(pvalue)\tfold_enrichment\t-log10(qvalue)\tname"}
        {print $1"\t"$2"\t"$3"\t"$3-$2+1"\t0\t0\t0\t0\t0\t"$4}' > `basename $0`
      doc: Tool converts `input_file` to the format compatible with the input of iaintersect from `assign_genes` step

  assign_genes:
    run: ../tools/iaintersect.cwl
    in:
      input_filename: bed_to_macs/output_file
      annotation_filename: annotation_file
      promoter_bp: promoter_bp
    out: [result_file]

  add_island_names:
    in:
      input_file: [assign_genes/result_file, sort_bed/sorted_file]
      param:
        source: bambai_pair
        valueFrom: $(self.location.split('/').slice(-1)[0].split('.').slice(0,-1).join('.')+"_default_s_enhcr.tsv")
    out: [output_file]
    run:
      cwlVersion: v1.0
      class: CommandLineTool
      requirements:
      - class: DockerRequirement
        dockerPull: biowardrobe2/scidap:v0.0.3
      inputs:
        input_file:
          type: File[]
          inputBinding:
            position: 5
          doc: TSV file to add extra columns too
        param:
          type: string
          inputBinding:
            position: 6
          doc: Param to set output filename
      outputs:
        output_file:
          type: File
          outputBinding:
            glob: "*"
      baseCommand: [bash, '-c']
      arguments:
      - echo -e "refseq_id\tgene_id\ttxStart\ttxEnd\tstrand\tchrom\tstart\tend\tlength\tregion\tname\tscore" > `basename $2`;
        cat $0 | grep -v refseq_id | paste - $1 | cut -f 1-9,15,19,20 >> `basename $2`

$namespaces:
  s: http://schema.org/

$schemas:
- http://schema.org/docs/schema_org_rdfa.html

s:name: "Super-enhancer post ChIP-Seq analysis"
label: "Super-enhancer post ChIP-Seq analysis"
s:alternateName: "Super Enhancer Analysis by Richard A. Young"

s:downloadUrl: https://raw.githubusercontent.com/datirium/workflows/master/workflows/super-enhancer.cwl
s:codeRepository: https://github.com/datirium/workflows
s:license: http://www.apache.org/licenses/LICENSE-2.0

s:isPartOf:
  class: s:CreativeWork
  s:name: Common Workflow Language
  s:url: http://commonwl.org/

s:creator:
- class: s:Organization
  s:legalName: "Cincinnati Children's Hospital Medical Center"
  s:location:
  - class: s:PostalAddress
    s:addressCountry: "USA"
    s:addressLocality: "Cincinnati"
    s:addressRegion: "OH"
    s:postalCode: "45229"
    s:streetAddress: "3333 Burnet Ave"
    s:telephone: "+1(513)636-4200"
  s:logo: "https://www.cincinnatichildrens.org/-/media/cincinnati%20childrens/global%20shared/childrens-logo-new.png"
  s:department:
  - class: s:Organization
    s:legalName: "Allergy and Immunology"
    s:department:
    - class: s:Organization
      s:legalName: "Barski Research Lab"
      s:member:
      - class: s:Person
        s:name: Michael Kotliar
        s:email: mailto:misha.kotliar@gmail.com
        s:sameAs:
        - id: http://orcid.org/0000-0002-6486-3898

doc: |
  Super-enhancers, consist of clusters of enhancers that are densely occupied by the master regulators and Mediator.
  Super-enhancers differ from typical enhancers in size, transcription factor density and content, ability to activate transcription,
  and sensitivity to perturbation.

  Use to create stitched enhancers, and to separate super-enhancers from typical enhancers using sequencing data (.bam) given a file of previously identified constituent enhancers (.gff)
