#!/usr/bin/env python
import os, tempfile, shutil, argparse
from xml.etree.ElementTree import ElementTree, Element
from subprocess import check_output
from packager.common import *

os.chdir(os.path.dirname(os.path.realpath(__file__)))

# Settings
# -----------------------------------------------------------------------
PACKAGE_NAME = 'SmoothMouse'
COMPONENT_IDENTIFIER_PREFIX = 'com.cyberic.pkg.SmoothMouse'
ROOT_DIR = 'Root'
PACKAGE_VERSION = read_version(os.path.join(ROOT_DIR, 'SmoothMouse.prefPane'), 'CFBundleShortVersionString')

# Elements: filename under ROOT_DIR, internal name without spaces, install location
COMPONENTS = (
	('SmoothMouse.kext', 'Kext', '/System/Library/Extensions/'),
	('SmoothMouse.prefPane', 'PrefPane', '/Library/PreferencePanes/'),
)

# Logic
# -----------------------------------------------------------------------
# Set up the command-line argument parser
parser = argparse.ArgumentParser()
parser.add_argument('--certificate', '-c', help='Certificate to sign the product archive with')
parser.add_argument('--key', '-k', help='Private key necessary to produce a DSA signature for Sparkle')
parser.add_argument('--reveal', action='store_true', help='Reveal the product archive in Finder upon completion')
args = parser.parse_args()

# Format version string
short_version = human_version = '.'.join(PACKAGE_VERSION[:3])
if len(PACKAGE_VERSION) > 3:
	human_version += ' (%s)' % PACKAGE_VERSION[3]

# Create a temporary directory for our dirty deeds
temp_dir = tempfile.mkdtemp()

# Copy resources into the temporary directory
if os.path.isdir('Resources'):
	resources = os.path.join(temp_dir, 'Resources')
	shutil.copytree('Resources', resources)
	
	# Patch Welcome.rtf to include version number
	welcome = os.path.join(resources, 'Welcome.rtf')
	replace_in_file(welcome, {'VERSION': human_version})

# Build component packages
components_dir = os.path.join(temp_dir, 'Components')
os.mkdir(components_dir)
for component in COMPONENTS:
	destination = os.path.join(components_dir, component[1] + '.pkg')
	pkgbuild(
		component=os.path.join(ROOT_DIR, component[0]),
		identifier=COMPONENT_IDENTIFIER_PREFIX+component[1],
		scripts=os.path.join('Scripts', component[1]),
		install_location=component[2],
		destination=destination,
	)
	
	# Hack to set BundleIsVersionChecked to False in an existing archive
	check_output(['pkgutil', '--expand', destination, os.path.join(components_dir, component[1])])
	package_info = os.path.join(components_dir, component[1], 'PackageInfo')
	tree = ElementTree()
	root = tree.parse(package_info)
	root.remove(root.find('bundle-version'))
	root.append(Element('bundle-version'))
	tree.write(package_info)
	check_output(['pkgutil', '--flatten', os.path.join(components_dir, component[1]), destination])

# Build a product archive
temp_product_path = os.path.join(temp_dir, PACKAGE_NAME + '.pkg')
productbuild(
	distribution='Distribution.xml',
	package_path=os.path.join(temp_dir, 'Components'),
	resources=os.path.join(temp_dir, 'Resources'),
	destination=temp_product_path,
)

# Sign the product archive with the Apple Developer ID
if args.certificate:
	final_product_path = PACKAGE_NAME + '.pkg'
	productsign('Developer ID Installer: ' + args.certificate, temp_product_path, final_product_path)
else:
	final_product_path = PACKAGE_NAME + ' (unsigned).pkg'
	shutil.copy(temp_product_path, final_product_path)

# Zip the product archive
final_archive_path = PACKAGE_NAME + ' %s.zip' % short_version
archive(final_product_path, final_archive_path)

# Produce a DSA signature for Sparkle
if args.key:
	print '	     DSA = ' + sign_update(args.key, final_archive_path)
	
# Delete the temporary directory
shutil.rmtree(temp_dir)

if args.reveal:
	osascript = '''
		tell application "Finder"
	 		activate
			reveal POSIX file "%s"
		end tell
		''' % os.path.abspath(final_archive_path)
	check_output("osascript -e '%s'" % osascript, shell=True)