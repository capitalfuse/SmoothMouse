import os, sys, fileinput, logging
from subprocess import check_output

logging.basicConfig(
	level=logging.DEBUG, 
	format='%(asctime)s %(levelname)s %(message)s',
	datefmt='%H:%M:%S',
)

# Auxiliary functions
# -----------------------------------------------------------------------
def check_required(*args):
	for arg in args[1:]:
		if not arg in args[0]:
			raise TypeError('Argument "%s" is required' % arg)
			
def prepare_options(*args):
	for arg in args[1:]:
		if arg in args[0]:
			yield '--' + arg.replace('_', '-'), str(args[0][arg])
			
def log_success():
	logging.info('Success' + "\n")

# Reading plists
# -----------------------------------------------------------------------
def defaults_read(filename, property):
	if not filename.endswith('.plist'):
		filename += '/Contents/Info.plist'
	
	if os.path.isfile(filename):
		return check_output(['defaults', 'read', os.path.abspath(filename), property])
	else:
		raise IOError('File not found')

def read_version(filename, property='CFBundleVersion'):	
	return defaults_read(filename, property).strip().split('.')
	
# File manipulation
# -----------------------------------------------------------------------
def replace_in_file(filename, replacements):
	for line in fileinput.input(filename, inplace=1):
		for search, replace in replacements.items():
			sys.stdout.write(line.replace('%' + search + '%', replace))

def check_file_existence(filename, success_callback=''):
	if os.path.isfile(filename) and os.path.getsize(filename) > 0:
		if success_callback:
			success_callback()
	else:
		raise Exception('Test failed: something is wrong with the file')

# Wrappers for console commands
# -----------------------------------------------------------------------
def pkgbuild(*args, **kwargs):
	check_required(kwargs, 'component', 'identifier', 'install_location', 'destination')
	options = dict(prepare_options(kwargs, 'component', 'identifier', 'install_location', 'scripts', 'version'))
	destination = kwargs['destination']
	
	# If version was not specified, read it from the component
	if not kwargs.get('version'):
		options['--version'] = '.'.join(read_version(kwargs['component']))
	
	# Finalize options and log the call
	logging.info('Building a component package with the following arguments:')
	options_list = []
	for key, value in options.items():
		logging.info('	%s: %s' % (key, value))
		options_list += [key, value]
	logging.info('Destination: %s' % destination)
	
	# Finally, run pkgbuild
	check_output(['pkgbuild'] + options_list + [destination])
	
	# Test existence of the package
	check_file_existence(destination, log_success)

def productbuild(*args, **kwargs):
	check_required(kwargs, 'distribution', 'package_path', 'destination')
	options = dict(prepare_options(kwargs, 'distribution', 'package_path', 'resources'))	
	destination = kwargs['destination']
		
	# Finalize options and log the call
	logging.info('Building a product archive with the following arguments:')
	options_list = []
	for key, value in options.items():
		logging.info('	%s: %s' % (key, value))
		options_list += [key, value]
	logging.info('Destination: %s' % destination)
		
	# Finally, run productbuild
	check_output(['productbuild'] + options_list + [destination])
	
	# Test existence of the package
	check_file_existence(destination, log_success)

def productsign(certificate_name, input_product_path, output_product_path):	
	logging.info('Signing the product archive with: ' + certificate_name)
	check_output(['productsign', '--sign', certificate_name, input_product_path, output_product_path])
	
	# Test existence of the package
	check_file_existence(output_product_path, log_success)
	
def archive(source, destination):
	logging.info('Creating a ZIP archive from ' + source)
	check_output(['zip', '-r', destination, source])
	
	# Test existence of the archive
	check_file_existence(destination, log_success)
	
	# Return some information about the archive
	info = "\n	filename = " + os.path.basename(destination)
	info += "\n	filesize = " + str(os.path.getsize(destination))
	info += "\n	     md5 = " + check_output(['openssl', 'md5', destination]).split('=')[1].strip()
	logging.info("Archive information:" + info)
	
def sign_update(certificate, archive):	
	return check_output(['./sign_update.rb', archive, certificate])