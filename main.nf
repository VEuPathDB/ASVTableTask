import nextflow.splitter.CsvSplitter

nextflow.enable.dsl=2


def fetchRunAccessions( tsv ) {
    def splitter = new CsvSplitter().options( header:true, sep:'\t' )
    def reader = new BufferedReader( new FileReader( tsv ) )
    splitter.parseHeader( reader )
    List<String> run_accessions = []
    Map<String,String> row
    while( row = splitter.fetchRecord( reader ) ) {
       run_accessions.add( row['run_accession'] )
    }
    return run_accessions
}


process downloadFiles {
  container ='veupathdb/bowtiemapping'  

  input:
    val id

  output:
    tuple val(id), path("${id}**.fastq")

  script:
    """
    fasterq-dump --split-3 ${id}
    """
}


process filterFastqs {
  input:
    tuple val(genomeName), path(fastqs)

  output:
    tuple val(genomeName), path('filtered/*.fast*')

  script:
    """
    mkdir filtered
    Rscript /usr/bin/filterFastqs.R \
      --fastqsInDir . \
      --fastqsOutDir ./filtered \
      --isPaired $params.isPaired \
      --trimLeft $params.trimLeft \
      --trimLeftR $params.trimLeftR \
      --truncLen $params.truncLen \
      --truncLenR $params.truncLenR \
      --maxLen $params.maxLen \
      --platform $params.platform
    """
}


process buildErrors {
  input:
    tuple val(genomeName), path(fastasfiltered)

  output:
    tuple val(genomeName), path('err.rds'), path('filtered/*.fast*')

  script:
    """
    Rscript /usr/bin/buildErrorsN.R \
      --fastqsInDir . \
      --errorsOutDir . \
      --errorsFileNameSuffix err.rds \
      --isPaired $params.isPaired \
      --platform $params.platform \
      --nValue $params.nValue
    mkdir filtered
    mv *.fastq filtered/
    """
}


process fastqToAsv {
  input:
    tuple val(genomeName), path('err.rds'), path(fastqsFiltered)

  output:
    tuple val(genomeName), path('featureTable.rds')

  script:
    """
    Rscript /usr/bin/fastqToAsv.R  \
      --fastqsInDir .  \
      --errorsRdsPath ./err.rds \
      --outRdsPath ./featureTable.rds \
      --isPaired $params.isPaired \
      --platform $params.platform \
      --mergeTechReps $params.mergeTechReps
    """
}


process mergeAsvsAndAssignToOtus {
  publishDir params.outputDir, mode: 'copy'

  input:
    tuple val(genomeName), path('featureTable.rds')

  output:
    path '*_output'
    path '*_output.bootstraps'
    path '*_output.full'

  script:
    """
    Rscript /usr/bin/mergeAsvsAndAssignToOtus.R \
      --asvRdsInDir . \
      --assignTaxonomyRefPath $params.trainingSet \
      --addSpeciesRefPath $params.speciesAssignment \
      --outPath ./"$genomeName"_output
    """
}


workflow {
  accessions = fetchRunAccessions( params.studyIdFile )
  ids = Channel.fromList( accessions )
  downloadFiles( ids ) \
    | filterFastqs \
    | buildErrors \
    | fastqToAsv \
    | mergeAsvsAndAssignToOtus
}