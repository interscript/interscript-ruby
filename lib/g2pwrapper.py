import g2p, SequiturTool
import numpy

def transliterate(word):

  class Struct:
      def __init__(self, **entries):
          self.__dict__.update(entries)

  options = Struct(**{'profile': None, 'resource_usage': None,
  'psyco': None, 'tempdir': None, 'trainSample': None, 'develSample':
  None, 'testSample': None, 'checkpoint': None,
  'resume_from_checkpoint': None, 'shouldTranspose': None,
  'modelFile': './lib/model-7', 'newModelFile': None,
  'shouldTestContinuously': None, 'shouldSelfTest': None,
  'lengthConstraints': None, 'shouldSuppressNewMultigrams': None,
  'viterbi': None, 'shouldRampUp': None, 'shouldWipeModel': None,
  'shouldInitializeWithCounts': None, 'minIterations': 20,
  'maxIterations': 100, 'eager_discount_adjustment': None,
  'fixed_discount': None, 'encoding': 'UTF-8', 'phoneme_to_phoneme':
  None, 'test_segmental': None, 'testResult': None, 'applySample':
  None, 'applyWord': word, 'variants_mass': None, 'variants_number':
  None, 'fakeTranslator': None, 'stack_limit': None})

  loadSample = g2p.loadG2PSample

  model = SequiturTool.procureModel(options, loadSample)
  if not model:
      return 1
  translator = g2p.Translator(model)
  del model

  # Keep only Thai strings

  return ''.join(translator(tuple(word)))