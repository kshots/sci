# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5

inherit alternatives-2 eutils fortran-2 git-r3 multilib multibuild toolchain-funcs

DESCRIPTION="Optimized BLAS library based on GotoBLAS2"
HOMEPAGE="http://xianyi.github.com/OpenBLAS/"
SRC_URI="http://dev.gentoo.org/~bicatali/distfiles/${PN}-gentoo.patch"
EGIT_REPO_URI="https://github.com/xianyi/OpenBLAS.git"
EGIT_BRANCH="develop"

LICENSE="BSD"
SLOT="0"
IUSE="dynamic int64 openmp static-libs threads"
KEYWORDS=""

INT64_SUFFIX="int64"
BASE_PROFNAME="openblas"

get_openblas_flags() {
	local openblas_flags=""
	use dynamic && \
		openblas_flags+=" DYNAMIC_ARCH=1 TARGET=GENERIC NUM_THREADS=64 NO_AFFINITY=1"
	if [[ "${MULTIBUILD_ID}" =~ "_${INT64_SUFFIX}" ]]; then
		openblas_flags+=" INTERFACE64=1 LIBNAMESUFFIX=${INT64_SUFFIX}"
	fi
	# choose posix threads over openmp when the two are set
	# yet to see the need of having the two profiles simultaneously
	if use threads; then
		openblas_flags+=" USE_THREAD=1 USE_OPENMP=0"
	elif use openmp; then
		openblas_flags+=" USE_THREAD=0 USE_OPENMP=1"
	fi
	echo "${openblas_flags}"
}

get_profname() {
	local profname="${BASE_PROFNAME}"
	use dynamic && \
		profname+="-dynamic"
	if [[ "${MULTIBUILD_ID}" =~ "_${INT64_SUFFIX}" ]]; then
		profname+="-${INT64_SUFFIX}"
	fi
	# choose posix threads over openmp when the two are set
	# yet to see the need of having the two profiles simultaneously
	if use threads; then
		profname+="-threads"
	elif use openmp; then
		profname+="-openmp"
	fi
	echo "${profname}"
}

pkg_setup() {
	# The file /usr/include/openblas/openblas_config.h is generated during the install.
	# By listing the int64 variant first, the int64 variant /usr/include/openblas/openblas_config.h
	# will be overwritten by the normal variant in the install, which removes the
	# #define OPENBLAS_USE64BITINT for us.  We then specify it in Cflags in the
	# /usr/lib64/pkg-config/openblas-int64-{threads,openmp}.pc file.
	MULTIBUILD_VARIANTS=()
	use int64 && \
		MULTIBUILD_VARIANTS+=( ${BASE_PROFNAME}_${INT64_SUFFIX} )
	MULTIBUILD_VARIANTS+=( ${BASE_PROFNAME} )
}

src_prepare() {
	multibuild_copy_sources
}

src_configure() {
	my_configure() {
		# lapack and lapacke are not modified from upstream lapack
		sed \
			-e "s:^#\s*\(CC\)\s*=.*:\1=$(tc-getCC):" \
			-e "s:^#\s*\(FC\)\s*=.*:\1=$(tc-getFC):" \
			-e "s:^#\s*\(COMMON_OPT\)\s*=.*:\1=${CFLAGS}:" \
			-e "s:^#\s*\(NO_LAPACK\)\s*=.*:\1=1:" \
			-e "s:^#\s*\(NO_LAPACKE\)\s*=.*:\1=1:" \
			-i Makefile.rule || die
	}
	multibuild_foreach_variant run_in_build_dir my_configure
}

src_compile() {
	# openblas already does multi-jobs
	MAKEOPTS+=" -j1"
	my_src_compile () {
		local openblas_flags=$(get_openblas_flags)
		local profname=$(get_profname)
		einfo "Compiling profile ${profname}"
		# cflags already defined twice
		unset CFLAGS
		emake clean
		emake libs shared ${openblas_flags}
		mkdir -p libs && mv libopenblas* libs/
		# avoid pic when compiling static libraries, so re-compiling
		if use static-libs; then
			emake clean
			emake libs ${openblas_flags} NO_SHARED=1 NEED_PIC=
			mv libopenblas* libs/
		fi
		cat <<-EOF > ${profname}.pc
			prefix=${EPREFIX}/usr
			libdir=\${prefix}/$(get_libdir)
			includedir=\${prefix}/include
			Name: ${PN}
			Description: ${DESCRIPTION}
			Version: ${PV}
			URL: ${HOMEPAGE}
			Libs: -L\${libdir} -l${MULTIBUILD_ID}
			Libs.private: -lm
		EOF
		if [[ "${MULTIBUILD_ID}" =~ "_${INT64_SUFFIX}" ]]; then
			cat <<-EOF >> ${profname}.pc
				Cflags: -DOPENBLAS_USE64BITINT -I\${includedir}/${PN}
				Fflags=-fdefault-integer-8
			EOF
		else
			cat <<-EOF >> ${profname}.pc
				Cflags: -I\${includedir}/${PN}
				Fflags=
			EOF
		fi
		mv libs/libopenblas* . || die
	}
	multibuild_foreach_variant run_in_build_dir my_src_compile
}

src_test() {
	my_src_test () {
		local openblas_flags=$(get_openblas_flags)
		emake tests ${openblas_flags}
	}
	multibuild_foreach_variant run_in_build_dir my_src_test
}

src_install() {
	my_src_install () {
		local openblas_flags=$(get_openblas_flags)
		local profname=$(get_profname)
		local pcfile
		for pcfile in *.pc; do
			local profname=${pcfile%.pc}
			emake install \
				PREFIX="${ED}"usr ${openblas_flags} \
				OPENBLAS_INCLUDE_DIR="${ED}"usr/include/${PN} \
				OPENBLAS_LIBRARY_DIR="${ED}"usr/$(get_libdir)
			use static-libs || rm "${ED}"usr/$(get_libdir)/lib*.a
			alternatives_for blas ${profname} 0 \
				/usr/$(get_libdir)/pkgconfig/blas.pc ${pcfile}
			alternatives_for cblas ${profname} 0 \
				/usr/$(get_libdir)/pkgconfig/cblas.pc ${pcfile} \
				/usr/include/cblas.h ${PN}/cblas.h
			insinto /usr/$(get_libdir)/pkgconfig
			doins ${pcfile}
		done

		if [[ ${CHOST} == *-darwin* ]] ; then
			cd "${ED}"/usr/$(get_libdir)
			local d
			for d in *.dylib ; do
				ebegin "Correcting install_name of ${d}"
				install_name_tool -id "${EPREFIX}/usr/$(get_libdir)/${d}" "${d}"
				eend $?
			done
		fi
	}
	multibuild_foreach_variant run_in_build_dir my_src_install

	dodoc GotoBLAS_{01Readme,03FAQ,04FAQ,05LargePage,06WeirdPerformance}.txt
	dodoc *md Changelog.txt
}
