import g2p, SequiturTool
import numpy

def transliterate(model, word):

  class Struct:
      def __init__(self, **entries):
          self.__dict__.update(entries)

  model_path = {
    'pythainlp_lexicon': './lib/model-7', 
    'wiktionary_phonemic': './lib/tha-pt-b-7'
  }

  connector_dict = {
    'pythainlp_lexicon': '', 
    'wiktionary_phonemic': '-'
  }


  modelFile = model_path[model]
  connector = connector_dict[model]

  options = Struct(**{'profile': None, 'resource_usage': None, 'psyco': None, 'tempdir': None, 'trainSample': None, 'develSample': None, 'testSample': None, 'checkpoint': None, 'resume_from_checkpoint': None, 'shouldTranspose': None, 'modelFile': modelFile , 'newModelFile': None, 'shouldTestContinuously': None, 'shouldSelfTest': None, 'lengthConstraints': None, 'shouldSuppressNewMultigrams': None, 'viterbi': None, 'shouldRampUp': None, 'shouldWipeModel': None, 'shouldInitializeWithCounts': None, 'minIterations': 20, 'maxIterations': 100, 'eager_discount_adjustment': None, 'fixed_discount': None, 'encoding': 'UTF-8', 'phoneme_to_phoneme': None, 'test_segmental': None, 'testResult': None, 'applySample': None, 'applyWord': word, 'variants_mass': None, 'variants_number': None, 'fakeTranslator': None, 'stack_limit': None})

  loadSample = g2p.loadG2PSample

  model = SequiturTool.procureModel(options, loadSample)
  if not model:
      return 1
  translator = g2p.Translator(model)
  del model

  return connector.join(translator(tuple(word)))