##
## TPKG - The Tcl Package Manager
##
## Copyright 2019-2023 Ben Fuhrmannek
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##

module common
module pkgdef_defauts
module tpkgdef_std_conf_make

tpkg_version=0.1dev2
tpkg_base="${TPKG_BASE:-/opt/tpkg}"

tpkg_pkgdefs="${TPKG_PKGDEFS:-$tpkg_base/tpkg/pkgdefs}"
tpkg_libdir="${TPKG_LIBDIR:-$tpkg_base/tpkg/lib}"
tpkg_receiptsdir="$tpkg_base/receipts"

script_dir="$( dirname "${BASH_SOURCE[0]}" )"
if [[ -d "$script_dir/pkgdefs" && -d "$script_dir/lib" ]]; then
	## dev mode
	tpkg_pkgdefs="$script_dir/pkgdefs"
	tpkg_libdir="$script_dir/lib"
fi

tpkg_workdir="${TPKG_WORKDIR:-$tpkg_base/work}"
tpkg_archivedir="${TPKG_ARCHIVEDIR:-$tpkg_base/cache}"
tpkg_tcllibdir="${TCL_PREFIX:-$tpkg_base}/lib"
tpkg_tclconfig="$tpkg_tcllibdir/tclConfig.sh"

CURL="${CURL:-curl}"

## flags

g_debug=0
g_nodeps=0

## checks

function error_renistall() {
	echo "Please reinstall tpkg or provide TPKG_BASE environment."
	exit 1
}

#if [[ ! -d "$tpkg_libdir" ]]; then
#	echo "$0: ERROR: lib dir not found: $tpkg_libdir"
#	error_renistall
#fi

if [[ ! -d "$tpkg_pkgdefs" ]]; then
	echo "$0: ERROR: pkgdefs not found: $tpkg_pkgdefs"
	error_renistall
fi

##

if [[ -f "$tpkg_tclconfig" ]]; then
	. "$tpkg_tclconfig"
	TCLSH="${TCL_EXEC_PREFIX:-$tpkg_base}/bin/tclsh"
fi
#. "$tpkg_libdir/common.sh"

##

function banner() {
	msg "This is TPKG, the Tcl Package Manager, version $tpkg_version (proof of concept)"
	msg "  (c) 2019-2023 Ben Fuhrmannek, licensed under the Apache 2.0 License"
	msg "  https://github.com/bef/tpkg"
	msg ""
	msg "   BASE: $tpkg_base"
	msg "PKGDEFS: $tpkg_pkgdefs"
	msg " LIBDIR: $tpkg_libdir"
	msg "    Tcl: $TCL_VERSION$TCL_PATCH_LEVEL"
	echo ""
}

## getopts
function parse_options() {
	local opt
	while getopts "vnh" opt; do
		case "$opt" in
			v) g_debug=1; msg_debug "verbose mode" ;;
			n) g_nodeps=1 ;;
			h)
				print_usage
				exit 0
				;;
			*) exit 1
		esac
	done
}

function print_usage() {
	msg "Usage: $0 [options] <CMD> ..."
	msg "  options:"
	msg "  -v  be verbose"
	msg "  -n  do not resolve dependencies"
	msg "  -h  show this help message"
	msg ""
	msg "<CMD> can be any of the following:"
	# msg "  search <expression>"
	msg "  list               list all available packages with short descriptions"
	msg "  list installed     list installed packages"
	msg "  info <pkg>         print package details"
	msg "  install [-f] <pkg...>"
	msg "  clean              remove cached downloads"
	msg_debug "  reset_all          remove all installed packages"
	msg_debug "OR do a more granular installation:"
	msg_debug "  download <pkg>     download source and verify checksum"
	msg_debug "  extract <pkg>      extract package to work dir"
	msg_debug "  build <pkg>        perform configure/make"
	msg_debug "  deploy <pkg>       make install / copy"
	msg_debug "  cleanup <pkg>      remove work dir"
	# msg "  uninstall <pkg...>"
}

##

function write_pkg_reciept() {
	if [[ -z "$pkg_name" ]]; then
		return 1
	fi
	local status="$1"
	if [[ ! -d "$tpkg_receiptsdir" ]]; then
		call mkdir -p "$tpkg_receiptsdir"
	fi
	echo "$pkg_version $status" >"$tpkg_receiptsdir/$pkg_name"
}

function read_pkg_receipt() {
	function set_pkg_status() {
		pkg_installed_version="$1"
		pkg_installed_status="$2"
	}
	if [[ -f "$tpkg_receiptsdir/$pkg_name" ]]; then
		set_pkg_status $(cat "$tpkg_receiptsdir/$pkg_name")
		return
	fi
	return 1
}

## INFO

function pkg_exists() {
	[[ -f "$tpkg_pkgdefs/$1.def" ]]
}

function read_pkg_info() {
	#. "$tpkg_libdir/pkgdef_defauts.sh"
	. "$tpkg_pkgdefs/$1.def"
	if [[ -z "$pkg_archive_filename" ]]; then
		pkg_archive_filename="${pkg_name}-${pkg_version}.$pkg_archive_extension"
	fi
	pkg_archive="$tpkg_archivedir/$pkg_archive_filename"
	pkg_workdir="$tpkg_workdir/$pkg_name"
	pkg_builddir="$pkg_workdir/src"
}

function checkarg_pkg() {
	local pkg_name="$1"
	if [[ -z "$pkg_name" ]]; then
		msg_error "do what?"
		return 1
	fi
	if ! pkg_exists "$pkg_name"; then
		msg_error "$pkg_name: not found"
		return 1
	fi
}

function do_info() {
	local pkg_name="$1"
	checkarg_pkg "$pkg_name"
	read_pkg_info "$pkg_name"
	msg "PACKAGE: $pkg_name: $pkg_desc"
	echo "VERSION: $pkg_version"
	echo "URL: $pkg_homepage"
	echo "DL INFO URL: $pkg_download_info_url"
	echo "DL URL: $pkg_url"
	echo "CHECKSUM: $pkg_checksum"
	echo ""
	echo "$pkg_description"
	echo "---"
}

## DOWNLOAD

function pkg_check_checksum() {
	if [[ ! -z "$pkg_checksum" ]]; then
		msg_debug "checking checksum"
		if ! check_checksum "$pkg_archive" "$pkg_checksum"; then
			msg_warning "found archive with invalid checksum: $pkg_archive (sha256:$(calculate_checksum sha256 "$pkg_archive"))"
			return 1
		fi
	else
		msg_warning "no checksum available"
	fi
}

function do_download() {
	local pkg_name="$1"
	checkarg_pkg "$pkg_name"
	read_pkg_info "$pkg_name"
	if [[ ! -d "$tpkg_archivedir" ]]; then
		msg_debug "creating archive dir $tpkg_archivedir"
		mkdir -p "$tpkg_archivedir"
	fi

	if [[ -f "$pkg_archive"  &&  ! -z "$pkg_checksum" ]]; then
		msg_debug "checking checksum"
		if ! check_checksum "$pkg_archive" "$pkg_checksum"; then
			msg_warning "found archive with invalid checksum. removing..."
			rm -f "$pkg_archive"
		fi
	fi
	if [[ -f "$pkg_archive" ]]; then
		msg "no need to download. archive is already there."
		return
	fi

	msg "downloading $pkg_name..."
	pkg_pre_download
	pkg_download
	pkg_post_download
}

## EXTRACT

function do_extract() {
	local pkg_name="$1"
	checkarg_pkg "$pkg_name"
	read_pkg_info "$pkg_name"
	if [[ ! -f "$pkg_archive" ]]; then
		msg_error "$pkg_archive: not found. try '$0 download $pkg_name' first"
		return 1
	fi

	if [[ ! -d "$pkg_builddir" ]]; then
		mkdir -p "$pkg_builddir"
	fi

	msg "extracting $pkg_name..."
	pkg_pre_extract
	pkg_extract
	pkg_post_extract
}

## CONFIGURE / MAKE

function do_build() {
	local pkg_name="$1"
	checkarg_pkg "$pkg_name"
	read_pkg_info "$pkg_name"

	if [[ ! -d "$pkg_builddir" ]]; then
		msg_error "$pkg_builddir: not found. try 'download' and 'extract' first"
		return 1
	fi

	msg "building $pkg_name..."
	pkg_pre_configure
	pkg_configure
	pkg_post_configure
	pkg_pre_make
	pkg_make
	pkg_post_make
}

## DEPLOY (after building)

function pkg_deploy_builddir() {
	call cp -a "$pkg_builddir" "$tpkg_tcllibdir/${pkg_name}${pkg_version}"
}
function do_deploy() {
	local pkg_name="$1"
	checkarg_pkg "$pkg_name"
	read_pkg_info "$pkg_name"

	if [[ ! -d "$pkg_builddir" ]]; then
		msg_error "$pkg_builddir: not found. try 'download', 'extract' and 'build' first"
		return 1
	fi

	msg "deploying $pkg_name..."
	pkg_pre_deploy
	pkg_deploy
	pkg_post_deploy
	write_pkg_reciept installed
}

## CLEANUP
function do_cleanup() {
	local pkg_name="$1"
	checkarg_pkg "$pkg_name"
	read_pkg_info "$pkg_name"

	if [[ -d "$pkg_workdir" ]]; then
		if readinput_yesno -d y "remove $pkg_name's work dir ($pkg_workdir)?"; then
			call rm -rf "$pkg_workdir"
		fi
	fi
}

function do_clean() {
	if readinput_yesno -d y "remove all archives in $tpkg_archivedir?"; then
		call rm -rf -- "$tpkg_archivedir"/*
	fi
}

function do_reset_all() {
	local -a dirlist=( "$tpkg_receiptsdir" "$tpkg_workdir" "$tpkg_base/jimtcl" )

	msg "Directories to remove:"
	for dir in "${dirlist[@]}"; do
		msg "$dir"
	done
	msg "$tpkg_base/{bin,include,lib,man,share}"

	if readinput_yesno -d n "DELETE THEM ALL?"; then
		call rm -rf -- "${dirlist[@]}" "$tpkg_base"/{bin,include,lib,man,share}
	fi
	if readinput_yesno -d n "remove all archives in $tpkg_archivedir?"; then
		call rm -rf -- "$tpkg_archivedir"/*
	fi
	call mkdir -p "$tpkg_base/bin"
	call ln -s "$tpkg_base/tpkg/tpkg" "$tpkg_base/bin/tpkg"
}

## complete install
function calculate_deps() (
	local -a pkglist
	function adddeps() {
		local dep
		read_pkg_info "$1"
		for dep in "${pkg_requires[@]}"; do
			if ! in_array "$dep" "${pkglist[@]}"; then
				adddeps "$dep"
				pkglist+=( "$dep" )
			fi
		done
	}
	for pkg_name in "$@"; do
		if [[ $g_nodeps -ne 1 ]]; then
			adddeps "$pkg_name"
		fi
		if ! in_array "$pkg_name" "${pkglist[@]}"; then
			pkglist+=( "$pkg_name" )
		fi
	done
	echo "${pkglist[*]}"
)

function do_install() {
	local force_install=0
	while true; do
		case "$1" in
		-f) force_install=1 ;;
		*) break ;;
		esac
		shift
	done

	for pkg_name in "$@"; do
		if ! pkg_exists "$pkg_name"; then
			msg_error "$pkg_name: package not found"
			return 1
		fi
	done

	local -a pkglist=( $(calculate_deps "$@") )

	for pkg_name in "${pkglist[@]}"; do
		if [[ $force_install -eq 0 ]] && read_pkg_receipt && [[ "$pkg_installed_status" == "installed" ]]; then
			msg_debug "$pkg_name is already installed"
			continue
		fi
		msg "Installing $pkg_name..."
		( do_download $pkg_name )
		( do_extract $pkg_name )
		( do_build $pkg_name )
		( do_deploy $pkg_name )
		if [[ $pkg_name == "tcl" && -f "$tpkg_tclconfig" ]]; then
			. "$tpkg_tclconfig"
		fi
		# ( do_cleanup $pkg_name )
	done
}

## LIST
function do_list() {
	case "$1" in
	i|installed)
		for pkg_name in $(ls "$tpkg_receiptsdir"|sort); do
			read_pkg_receipt
			if [[ "$pkg_installed_status" != "installed" ]]; then
				continue
			fi
			echo "$pkg_name $pkg_installed_version $pkg_installed_status"
		done
	;;
	*)
		set +e
		for pkg_name in $(ls $tpkg_pkgdefs/*.def |xargs basename -s .def); do
			(
				set -e
				read_pkg_info "$pkg_name"
				echo "$pkg_name $pkg_version"
				echo "  $pkg_desc"
				echo ""
			)
		done
	;;
	esac
	return
}

##

main () {
banner
parse_options "$@"; shift $((OPTIND-1))

if [[ $# -ge 1 ]]; then
	if [[ "$(type -t "do_$1")" == "function" ]]; then
		(
			set -e
			"do_$1" "${@:2}"
		)
		if [[ $? -ne 0 ]]; then
			msg_error "command failed"
		fi
	else
		msg_error "$1: command not found"
		exit 1
	fi
	msg "done."
else
	print_usage
	echo -e "\nBye."
fi
}
