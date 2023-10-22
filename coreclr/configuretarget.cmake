
include(configurepaths.cmake)
include(configuretools.cmake)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

include(GNUInstallDirs)
include(CheckIncludeFile)
include(CheckFunctionExists)
include(TestBigEndian)
include(CheckCCompilerFlag)

function(append value)
  foreach(variable ${ARGN})
    set(${variable} "${${variable}} ${value}" PARENT_SCOPE)
  endforeach(variable)
endfunction()

if((CMAKE_CXX_COMPILER_ID STREQUAL "GNU") OR(CMAKE_CXX_COMPILER_ID STREQUAL "Clang") OR(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang"))
  set(GCC 1)
endif()

add_definitions(-DHAVE_CONFIG_H)

# if(GCC)
#   add_definitions(-g)  # TODO: should this really be on by default?
#   add_definitions(-fPIC)
#   add_definitions(-fvisibility=hidden)
#   set(USE_GCC_ATOMIC_OPS 1)
# endif()

######################################
# HOST OS CHECKS
######################################

message (STATUS "CMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}")

set(CLR_CMAKE_HOST_OS ${CMAKE_SYSTEM_NAME})
string(TOLOWER ${CLR_CMAKE_HOST_OS} CLR_CMAKE_HOST_OS)

if(CLR_CMAKE_HOST_OS STREQUAL "darwin")
  add_definitions(-D_THREAD_SAFE)
  set(HOST_DARWIN 1)
  set(HOST_OSX 1)
  set(PTHREAD_POINTER_ID 1)
  set(USE_MACH_SEMA 1)
  if(CMAKE_SYSTEM_VARIANT STREQUAL "maccatalyst")
    set(HOST_MACCAT 1)
  endif()
elseif(CLR_CMAKE_HOST_OS STREQUAL "ios" OR CLR_CMAKE_HOST_OS STREQUAL "tvos")
  # See man cmake-toolchains(7) on which variables
  # control cross-compiling to ios
  add_definitions(-D_THREAD_SAFE)
  set(HOST_DARWIN 1)
  if(CLR_CMAKE_HOST_OS STREQUAL "ios")
    set(HOST_IOS 1)
  elseif(CLR_CMAKE_HOST_OS STREQUAL "tvos")
    set(HOST_TVOS 1)
  endif()
  set(PTHREAD_POINTER_ID 1)
  set(USE_MACH_SEMA 1)
  set(DISABLE_EXECUTABLES 1)
  set(TARGET_APPLE_MOBILE 1)
  add_definitions("-DSMALL_CONFIG")
  add_definitions("-D_XOPEN_SOURCE")
  add_definitions("-DHAVE_LARGE_FILE_SUPPORT=1")
elseif(CLR_CMAKE_HOST_OS STREQUAL "linux")
  set(HOST_LINUX 1)
  add_definitions(-D_GNU_SOURCE -D_REENTRANT)
  add_definitions(-D_THREAD_SAFE)
  # Enable the "full RELRO" options (RELRO & BIND_NOW) at link time
  add_link_options("LINKER:-z,relro")
  add_link_options("LINKER:-z,now")
elseif(CLR_CMAKE_HOST_OS STREQUAL "android")
  set(HOST_LINUX 1)
  add_definitions(-D_GNU_SOURCE -D_REENTRANT)
  add_definitions(-D_THREAD_SAFE)
  add_compile_options(-Wl,-z,now)
  add_compile_options(-Wl,-z,relro)
  add_compile_options(-Wl,-z,noexecstack)
  # The normal check fails because it uses --isystem <ndk root>/sysroot/usr/include
  set(HAVE_USR_INCLUDE_MALLOC_H 1)
  set(HOST_ANDROID 1)
  set(DISABLE_EXECUTABLES 1)
  # Force some defines
  set(HAVE_SCHED_GETAFFINITY 0)
  set(HAVE_SCHED_SETAFFINITY 0)
  # FIXME: Rest of the flags from configure.ac
elseif(CLR_CMAKE_HOST_OS STREQUAL "emscripten")
  set(HOST_BROWSER 1)
  add_definitions(-DNO_GLOBALIZATION_SHIM)
  add_definitions(-D_THREAD_SAFE)
  add_compile_options(-Wno-strict-prototypes)
  add_compile_options(-Wno-unused-but-set-variable)
  add_compile_options(-Wno-single-bit-bitfield-constant-conversion)
  set(DISABLE_EXECUTABLES 1)
  # FIXME: Is there a cmake option for this ?
  set(DISABLE_SHARED_LIBS 1)
  # sys/random.h exists, but its not found
  set(HAVE_SYS_RANDOM_H 1)
  set(INTERNAL_ZLIB 1)
elseif(CLR_CMAKE_HOST_OS STREQUAL "wasi")
  set(HOST_WASI 1)
  add_definitions(-D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_MMAN -DHOST_WASI)
  add_definitions(-DNO_GLOBALIZATION_SHIM)
  add_definitions(-D_THREAD_SAFE)
  add_definitions(-DDISABLE_SOCKET_TRANSPORT)
  add_definitions(-DDISABLE_EGD_SOCKET)
  add_definitions(-DDISABLE_EVENTPIPE)
  add_compile_options(-Wno-strict-prototypes)
  add_compile_options(-Wno-unused-but-set-variable)
  set(ENABLE_PERFTRACING 0)
  set(DISABLE_SHARED_LIBS 1)
  set(INTERNAL_ZLIB 1)
  set(DISABLE_EXECUTABLES 1)
  set(STATIC_COMPONENTS 1)
elseif(CLR_CMAKE_HOST_OS STREQUAL "windows")
  set(HOST_WIN32 1)
  set(EXE_SUFFIX ".exe")
  set(HOST_NO_SYMLINKS 1)
  set(INTERNAL_ZLIB 1)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>") # statically link VC runtime library
  add_compile_options(/W4)   # set warning level 4
  add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:/WX>) # treat warnings as errors
  add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:/wd4324>) # 'struct_name' : structure was padded due to __declspec(align())
  add_compile_options(/EHsc) # set exception handling behavior
  add_compile_options(/FC)   # use full pathnames in diagnostics
  add_link_options(/STACK:0x800000)  # set stack size to 8MB (default is 1MB)
  if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_compile_options(/Oi)   # enable intrinsics
    add_compile_options(/GF)   # enable string pooling
    add_compile_options(/Zi)   # enable debugging information
    add_compile_options(/GL)   # whole program optimization
    add_link_options(/LTCG)    # link-time code generation
    add_link_options(/DEBUG)   # enable debugging information
    add_link_options(/OPT:REF) # optimize: remove unreferenced functions & data
    add_link_options(/OPT:ICF) # optimize: enable COMDAT folding
    # the combination of /Zi compiler flag and /DEBUG /OPT:REF /OPT:ICF
    # linker flags is needed to create .pdb output on release builds
  endif()
elseif(CLR_CMAKE_HOST_OS STREQUAL "sunos")
  set(HOST_SOLARIS 1)
  add_definitions(-DGC_SOLARIS_THREADS -DGC_SOLARIS_PTHREADS -D_REENTRANT -D_POSIX_PTHREAD_SEMANTICS -DUSE_MMAP -DUSE_MUNMAP -DHOST_SOLARIS -D__EXTENSIONS__ -D_XPG4_2)
elseif(CLR_CMAKE_HOST_OS STREQUAL "freebsd")
  set(HOST_FREEBSD 1)
else()
  message(FATAL_ERROR "Host '${CLR_CMAKE_HOST_OS}' not supported.")
endif()

message(STATUS "CLR_CMAKE_HOST_OS=${CLR_CMAKE_HOST_OS}")

######################################
# TARGET OS CHECKS
######################################

if(NOT TARGET_SYSTEM_NAME)
  set(TARGET_SYSTEM_NAME "${CLR_CMAKE_HOST_OS}")
endif()

if(TARGET_SYSTEM_NAME STREQUAL "darwin")
  set(TARGET_UNIX 1)
  set(TARGET_MACH 1)
  set(TARGET_OSX 1)
  set(TARGET_DARWIN 1)
  if(CMAKE_SYSTEM_VARIANT STREQUAL "maccatalyst")
    set(TARGET_MACCAT 1)
  endif()
elseif(TARGET_SYSTEM_NAME STREQUAL "ios" OR TARGET_SYSTEM_NAME STREQUAL "tvos")
  set(TARGET_UNIX 1)
  set(TARGET_MACH 1)
  set(TARGET_DARWIN 1)
  set(TARGET_APPLE_MOBILE 1)
  if(TARGET_SYSTEM_NAME STREQUAL "ios")
    set(TARGET_IOS 1)
  elseif(TARGET_SYSTEM_NAME STREQUAL "tvos")
    set(TARGET_TVOS 1)
  endif()
elseif(TARGET_SYSTEM_NAME STREQUAL "linux")
  set(TARGET_UNIX 1)
  set(TARGET_LINUX 1)
elseif(TARGET_SYSTEM_NAME STREQUAL "alpine")
  set(TARGET_UNIX 1)
  set(TARGET_LINUX 1)
  set(TARGET_LINUX_MUSL 1)
elseif(TARGET_SYSTEM_NAME STREQUAL "android")
  set(TARGET_UNIX 1)
  set(TARGET_LINUX_BIONIC 1)
  set(TARGET_ANDROID 1)
  if (CMAKE_BUILD_TYPE STREQUAL "Release")
    add_compile_options(-O2)
  endif()
elseif(TARGET_SYSTEM_NAME STREQUAL "emscripten")
  set(TARGET_BROWSER 1)
  if (CMAKE_BUILD_TYPE STREQUAL "Release")
    add_compile_options(-Os)
  endif()
elseif(TARGET_SYSTEM_NAME STREQUAL "wasi")
  set(TARGET_WASI 1)
  set(DISABLE_THREADS 1)
  if (CMAKE_BUILD_TYPE STREQUAL "Release")
    add_compile_options(-Os)
  endif()
elseif(TARGET_SYSTEM_NAME STREQUAL "windows")
  set(TARGET_WIN32 1)
  set(TARGET_WINDOWS 1)
elseif(TARGET_SYSTEM_NAME STREQUAL "sunos")
  set(TARGET_UNIX 1)
  set(TARGET_SOLARIS 1)
elseif(TARGET_SYSTEM_NAME STREQUAL "freebsd")
  set(TARGET_UNIX 1)
  set(TARGET_FREEBSD 1)
else()
  message(FATAL_ERROR "Target '${TARGET_SYSTEM_NAME}' not supported.")
endif()

message(STATUS "TARGET_SYSTEM_NAME=${TARGET_SYSTEM_NAME}")

######################################
# HOST ARCH CHECKS
######################################

if(NOT "${CMAKE_OSX_ARCHITECTURES}" STREQUAL "")
  set(CMAKE_SYSTEM_PROCESSOR "${CMAKE_OSX_ARCHITECTURES}")
endif()

if(NOT "${MSVC_C_ARCHITECTURE_ID}" STREQUAL "")
  set(CMAKE_SYSTEM_PROCESSOR "${MSVC_C_ARCHITECTURE_ID}")
endif()

# Unify naming
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "armv7l" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "ARMV7")
  set(CMAKE_SYSTEM_PROCESSOR "arm")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "i686" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "i386" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "X86")
  set(CMAKE_SYSTEM_PROCESSOR "x86")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
  set(CMAKE_SYSTEM_PROCESSOR "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "amd64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "x64")
  set(CMAKE_SYSTEM_PROCESSOR "x86_64")
endif()

message (STATUS "CMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}")

if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  set(HOST_AMD64 1)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86")
  set(HOST_X86 1)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
  set(HOST_ARM64 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(HOST_ARM 1)
  # fixme: use separate defines for host/target
  set(NO_UNALIGNED_ACCESS 1)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "riscv64")
  set(HOST_RISCV 1)
  set(HOST_RISCV64 1)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "s390x")
  set(HOST_S390X 1)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "wasm" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "wasm32")
  set(HOST_WASM 1)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "ppc64le")
  set(HOST_POWERPC 1)
  set(HOST_POWERPC64 1)
else()
  message(FATAL_ERROR "CMAKE_SYSTEM_PROCESSOR='${CMAKE_SYSTEM_PROCESSOR}' not supported.")
endif()

######################################
# TARGET ARCH CHECKS
######################################

if(NOT TARGET_ARCH)
  set(TARGET_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
endif()

# Unify naming
if(TARGET_ARCH STREQUAL "armv7l" OR TARGET_ARCH STREQUAL "ARMV7")
  set(TARGET_ARCH "arm")
elseif(TARGET_ARCH STREQUAL "i686" OR TARGET_ARCH STREQUAL "i386" OR TARGET_ARCH STREQUAL "X86")
  set(TARGET_ARCH "x86")
elseif(TARGET_ARCH STREQUAL "aarch64" OR TARGET_ARCH STREQUAL "ARM64")
  set(TARGET_ARCH "arm64")
elseif(TARGET_ARCH STREQUAL "AMD64" OR TARGET_ARCH STREQUAL "x64")
  set(TARGET_ARCH "x86_64")
endif()

if(TARGET_ARCH STREQUAL "x86_64")
  set(TARGET_AMD64 1)
  set(MSPAL_ARCHITECTURE "\"amd64\"")
  set(TARGET_SIZEOF_VOID_P 8)
  set(SIZEOF_REGISTER 8)
elseif(TARGET_ARCH STREQUAL "x86")
  set(TARGET_X86 1)
  set(MSPAL_ARCHITECTURE "\"x86\"")
  set(TARGET_SIZEOF_VOID_P 4)
  set(SIZEOF_REGISTER 4)
elseif(TARGET_ARCH STREQUAL "arm64")
  set(TARGET_ARM64 1)
  set(MSPAL_ARCHITECTURE "\"arm64\"")
  set(TARGET_SIZEOF_VOID_P 8)
  set(SIZEOF_REGISTER 8)
  if(TARGET_SYSTEM_NAME STREQUAL "watchos")
    set(TARGET_SIZEOF_VOID_P 4)
    set(MSPAL_ARCH_ILP32 1)
  endif()
elseif(TARGET_ARCH MATCHES "arm")
  set(TARGET_ARM 1)
  set(MSPAL_ARCHITECTURE "\"arm\"")
  if(MSPAL_ARM_FPU STREQUAL "none")
    add_definitions("-DARM_FPU_NONE=1")
  elseif(MSPAL_ARM_FPU STREQUAL "vfp-hard")
    add_definitions("-DARM_FPU_VFP_HARD=1")
  else()
    add_definitions("-DARM_FPU_VFP=1")
  endif()
  set(TARGET_SIZEOF_VOID_P 4)
  set(SIZEOF_REGISTER 4)
  # fixme: use separate defines for host/target
  set(NO_UNALIGNED_ACCESS 1)
  set(HAVE_ARMV5 1)
  set(HAVE_ARMV6 1)
  #set(HAVE_ARMV7 1) # TODO: figure out if we should set this
elseif(TARGET_ARCH STREQUAL "riscv64")
  set(TARGET_RISCV 1)
  set(TARGET_RISCV64 1)
  set(MSPAL_ARCHITECTURE "\"riscv64\"")
  set(TARGET_SIZEOF_VOID_P 8)
  set(SIZEOF_REGISTER 8)
elseif(TARGET_ARCH STREQUAL "s390x")
  set(TARGET_S390X 1)
  set(MSPAL_ARCHITECTURE "\"s390x\"")
  set(TARGET_SIZEOF_VOID_P 8)
  set(SIZEOF_REGISTER 8)
elseif(TARGET_ARCH STREQUAL "wasm" OR TARGET_ARCH STREQUAL "wasm32")
  set(TARGET_WASM 1)
  set(MSPAL_ARCHITECTURE "\"wasm\"")
  set(TARGET_SIZEOF_VOID_P 4)
  set(SIZEOF_REGISTER 4)
elseif(TARGET_ARCH STREQUAL "ppc64le")
  set(TARGET_POWERPC 1)
  set(TARGET_POWERPC64 1)
  set(MSPAL_ARCHITECTURE "\"ppc64le\"")
  set(TARGET_SIZEOF_VOID_P 8)
  set(SIZEOF_REGISTER 8)
else()
  message(FATAL_ERROR "TARGET_ARCH='${TARGET_ARCH}' not supported.")
endif()

# arm64 MacCatalyst runtime host or AOT target is more like Apple mobile targets than x64
if ((HOST_MACCAT AND HOST_ARM64) OR (TARGET_MACCAT AND TARGET_ARM64))
  set(TARGET_APPLE_MOBILE 1)
endif()

include(${CLR_SRC_NATIVE_DIR}/external/zlib.cmake)

# # Decide if we need zlib, and if so whether we want the system zlib or the in-tree copy.
# if(NOT DISABLE_EMBEDDED_PDB OR NOT DISABLE_LOG_PROFILER_GZ)
#   if(INTERNAL_ZLIB)
#     # defines ZLIB_SOURCES
#     include(${CLR_SRC_NATIVE_DIR}/external/zlib.cmake)
#   else()
#     # if we're not on a platform where we use the in-tree zlib, require system zlib
#     include(${CLR_SRC_NATIVE_DIR}/libs/System.IO.Compression.Native/extra_libs.cmake)
#     set(Z_LIBS)
#     append_extra_compression_libs(Z_LIBS)
#   endif()
# endif()

######################################
# GCC CHECKS
######################################

if(GCC)
  # We require C11 with some GNU extensions, e.g. `linux` macro
  set(CMAKE_C_EXTENSIONS ON)

  # Turn off floating point expression contraction because it is considered a value changing
  # optimization in the IEEE 754 specification and is therefore considered unsafe.
  add_compile_options(-ffp-contract=off)

  # The runtime code does not respect ANSI C strict aliasing rules
  append("-fno-strict-aliasing" CMAKE_C_FLAGS CMAKE_CXX_FLAGS)
  # We rely on signed overflow to behave
  append("-fwrapv" CMAKE_C_FLAGS CMAKE_CXX_FLAGS)

  set(WARNINGS "-Wall -Wunused -Wmissing-declarations -Wpointer-arith -Wno-cast-qual -Wwrite-strings -Wno-switch -Wno-switch-enum -Wno-unused-value -Wno-attributes -Wno-format-zero-length -Wno-unused-function")
  set(WARNINGS_C "-Wmissing-prototypes -Wstrict-prototypes -Wnested-externs")

  set(WERROR "-Werror=return-type")
  set(WERROR_C "-Werror=implicit-function-declaration")

  if (CMAKE_C_COMPILER_ID MATCHES "Clang")
    set(WARNINGS "${WARNINGS} -Qunused-arguments -Wno-tautological-compare -Wno-parentheses-equality -Wno-self-assign -Wno-return-stack-address -Wno-constant-logical-operand -Wno-zero-length-array -Wno-asm-operand-widths")
  endif()

  check_c_compiler_flag("-Werror=incompatible-pointer-types" WERROR_INCOMPATIBLE_POINTER_TYPES)
  if(WERROR_INCOMPATIBLE_POINTER_TYPES)
    set(WERROR_C "${WERROR_C} -Werror=incompatible-pointer-types")
  endif()

  # Check for sometimes suppressed warnings
  check_c_compiler_flag(-Wreserved-identifier COMPILER_SUPPORTS_W_RESERVED_IDENTIFIER)
  if(COMPILER_SUPPORTS_W_RESERVED_IDENTIFIER)
    add_compile_definitions(COMPILER_SUPPORTS_W_RESERVED_IDENTIFIER)
  endif()

  if(HOST_WASI)
    # When building under WASI SDK, it's stricter about discarding 'const' qualifiers, causing some existing
    # code (e.g., mono-rand.c:315) to be rejected
    set(WERROR_C "${WERROR_C} -Wno-incompatible-pointer-types-discards-qualifiers")
  endif()

  append("${WARNINGS} ${WARNINGS_C} ${WERROR} ${WERROR_C}" CMAKE_C_FLAGS)
  append("${WARNINGS} ${WERROR}" CMAKE_CXX_FLAGS)

  set(MSPAL_ZERO_LEN_ARRAY 0)

  if(ENABLE_WERROR)
    append("-Werror" CMAKE_C_FLAGS CMAKE_CXX_FLAGS)
  endif()
endif()

######################################
# LLVM CHECKS
######################################
set(LLVM_LIBS)
if(LLVM_PREFIX)
  if(TARGET_ARCH STREQUAL "x86_64")
    set(llvm_codegen_libs "x86codegen")
  elseif(TARGET_ARCH STREQUAL "x86")
    set(llvm_codegen_libs "x86codegen")
  elseif(TARGET_ARCH STREQUAL "arm64")
    set(llvm_codegen_libs "aarch64codegen")
  elseif(TARGET_ARCH STREQUAL "arm")
    set(llvm_codegen_libs "armcodegen")
  elseif(TARGET_ARCH STREQUAL "wasm")
    set(llvm_codegen_libs "")
  else()
    message(FATAL_ERROR "FIXME: ${TARGET_ARCH}")
  endif()

  set(llvm_config_path "${LLVM_PREFIX}/include/llvm/Config/llvm-config.h")

  # llvm-config --mono-api-version
  file(STRINGS ${llvm_config_path} llvm_api_version_line REGEX "MSPAL_API_VERSION ")
  string(REGEX REPLACE ".*MSPAL_API_VERSION ([0-9]+)" "\\1" llvm_api_version ${llvm_api_version_line})

  # llvm-config --libs analysis core bitwriter mcjit orcjit
  set(MSPAL_llvm_core_libs "LLVMOrcJIT" "LLVMPasses" "LLVMCoroutines" "LLVMipo" "LLVMInstrumentation" "LLVMVectorize" "LLVMScalarOpts" "LLVMLinker" "LLVMIRReader" "LLVMAsmParser" "LLVMInstCombine" "LLVMFrontendOpenMP" "LLVMAggressiveInstCombine" "LLVMTransformUtils" "LLVMJITLink" "LLVMMCJIT" "LLVMExecutionEngine" "LLVMTarget" "LLVMRuntimeDyld" "LLVMBitWriter" "LLVMAnalysis" "LLVMProfileData" "LLVMObject" "LLVMTextAPI" "LLVMMCParser" "LLVMMC" "LLVMDebugInfoCodeView" "LLVMBitReader" "LLVMCore" "LLVMRemarks" "LLVMBitstreamReader" "LLVMBinaryFormat" "LLVMSupport" "LLVMDemangle")
  if(${llvm_api_version} LESS 1600)
    set(MSPAL_llvm_core_libs ${MSPAL_llvm_core_libs} "LLVMObjCARCOpts" "LLVMMCDisassembler" "LLVMOrcTargetProcess" "LLVMOrcShared" "LLVMDebugInfoDWARF")
  else()
    set(MSPAL_llvm_core_libs ${MSPAL_llvm_core_libs} "LLVMIRPrinter" "LLVMCodeGen" "LLVMObjCARCOpts" "LLVMMCDisassembler" "LLVMWindowsDriver" "LLVMOption" "LLVMOrcTargetProcess" "LLVMOrcShared"  "LLVMSymbolize" "LLVMDebugInfoPDB" "LLVMDebugInfoMSF" "LLVMDebugInfoDWARF" "LLVMTargetParser")
  endif()

  # llvm-config --libs x86codegen
  set(MSPAL_llvm_extra_libs_x86codegen "LLVMX86CodeGen" "LLVMCFGuard" "LLVMGlobalISel" "LLVMX86Desc" "LLVMX86Info" "LLVMMCDisassembler" "LLVMSelectionDAG" "LLVMAsmPrinter" "LLVMDebugInfoDWARF" "LLVMCodeGen" "LLVMTarget" "LLVMScalarOpts" "LLVMInstCombine" "LLVMAggressiveInstCombine" "LLVMTransformUtils" "LLVMBitWriter" "LLVMAnalysis" "LLVMProfileData" "LLVMObject" "LLVMTextAPI" "LLVMMCParser" "LLVMMC" "LLVMDebugInfoCodeView" "LLVMDebugInfoMSF" "LLVMBitReader" "LLVMCore" "LLVMRemarks" "LLVMBitstreamReader" "LLVMBinaryFormat" "LLVMSupport" "LLVMDemangle")
  if(${llvm_api_version} GREATER_EQUAL 1600)
    set(MSPAL_llvm_extra_libs_x86codegen ${MSPAL_llvm_extra_libs_x86codegen} "LLVMInstrumentation" "LLVMObjCARCOpts" "LLVMSymbolize" "LLVMDebugInfoPDB" "LLVMIRReader" "LLVMAsmParser" "LLVMTargetParser")
  endif()

  # llvm-config --libs armcodegen
  set(MSPAL_llvm_extra_libs_armcodegen "LLVMARMCodeGen" "LLVMCFGuard" "LLVMGlobalISel" "LLVMSelectionDAG" "LLVMAsmPrinter" "LLVMDebugInfoDWARF" "LLVMCodeGen" "LLVMTarget" "LLVMScalarOpts" "LLVMInstCombine" "LLVMAggressiveInstCombine" "LLVMTransformUtils" "LLVMBitWriter" "LLVMAnalysis" "LLVMProfileData" "LLVMObject" "LLVMTextAPI" "LLVMMCParser" "LLVMBitReader" "LLVMCore" "LLVMRemarks" "LLVMBitstreamReader" "LLVMARMDesc" "LLVMMCDisassembler" "LLVMMC" "LLVMDebugInfoCodeView" "LLVMDebugInfoMSF" "LLVMBinaryFormat" "LLVMARMUtils" "LLVMARMInfo" "LLVMSupport" "LLVMDemangle")
  if(${llvm_api_version} GREATER_EQUAL 1600)
    set(MSPAL_llvm_extra_libs_armcodegen ${MSPAL_llvm_extra_libs_armcodegen} "LLVMipo" "LLVMInstrumentation" "LLVMVectorize" "LLVMLinker" "LLVMFrontendOpenMP" "LLVMObjCARCOpts" "LLVMSymbolize" "LLVMDebugInfoPDB"  "LLVMIRReader" "LLVMAsmParser" "LLVMTargetParser")
  endif()

  # llvm-config --libs aarch64codegen
  set(MSPAL_llvm_extra_libs_aarch64codegen "LLVMAArch64CodeGen" "LLVMCFGuard" "LLVMGlobalISel" "LLVMSelectionDAG" "LLVMAsmPrinter" "LLVMDebugInfoDWARF" "LLVMCodeGen" "LLVMTarget" "LLVMScalarOpts" "LLVMInstCombine" "LLVMAggressiveInstCombine" "LLVMTransformUtils" "LLVMBitWriter" "LLVMAnalysis" "LLVMProfileData" "LLVMObject" "LLVMTextAPI" "LLVMMCParser" "LLVMBitReader" "LLVMCore" "LLVMRemarks" "LLVMBitstreamReader" "LLVMAArch64Desc" "LLVMMC" "LLVMDebugInfoCodeView" "LLVMDebugInfoMSF" "LLVMBinaryFormat" "LLVMAArch64Utils" "LLVMAArch64Info" "LLVMSupport" "LLVMDemangle")
  if(${llvm_api_version} GREATER_EQUAL 1600)
    set(MSPAL_llvm_extra_libs_aarch64codegen ${MSPAL_llvm_extra_libs_aarch64codegen} "LLVMObjCARCOpts" "LLVMSymbolize" "LLVMDebugInfoPDB"  "LLVMIRReader" "LLVMAsmParser" "LLVMTargetParser")
  endif()

  if(HOST_LINUX AND NOT HOST_WASM AND NOT HOST_WASI AND ${llvm_api_version} GREATER_EQUAL 1600)
    set(MSPAL_stdlib "-stdlib=libc++")
    set(MSPAL_cxx_lib "-L${LLVM_PREFIX}/lib -lc++")
    set(MSPAL_cxx_include "-I${LLVM_PREFIX}/include/c++/v1")
  endif()

  if(${llvm_api_version} GREATER_EQUAL 1600)
    if(HOST_WIN32)
      set(MSPAL_cxx_std_version "/std:c++17")
    else()
      set(MSPAL_cxx_std_version "-std=c++17")
    endif()
  else()
    if(HOST_WIN32)
      set(MSPAL_cxx_std_version "/std:c++14")
    else()
      set(MSPAL_cxx_std_version "-std=c++14")
    endif()
  endif()

  # llvm-config --cflags
  set(llvm_cflags "-I${LLVM_PREFIX}/include -D__STDC_CONSTANT_MACROS -D__STD_FORMAT_MACROS -D__STDC_LIMIT_MACROS")

  if (HOST_BROWSER)
    set(llvm_cxxflags "-I${LLVM_PREFIX}/include ${MSPAL_cxx_include} ${MSPAL_cxx_std_version} ${MSPAL_stdlib} -fno-rtti -D__STDC_CONSTANT_MACROS -D__STD_FORMAT_MACROS -D__STDC_LIMIT_MACROS")
  else()
    set(llvm_cxxflags "-I${LLVM_PREFIX}/include ${MSPAL_cxx_include} ${MSPAL_cxx_std_version} ${MSPAL_stdlib} -fno-exceptions -fno-rtti -D__STDC_CONSTANT_MACROS -D__STD_FORMAT_MACROS -D__STDC_LIMIT_MACROS")
  endif()
  set(llvm_includedir "${LLVM_PREFIX}/include")

  if(HOST_LINUX)
    # llvm-config --system-libs
    set(llvm_system_libs ${MSPAL_cxx_lib} "-lz" "-lrt" "-ldl" "-lpthread" "-lm")
  elseif(HOST_OSX)
    # llvm-config --system-libs
    set(llvm_system_libs "-lz" "-lm")
  endif()

  # llvm-config --libs analysis core bitwriter mcjit orcjit
  set(llvm_core_libs ${MSPAL_llvm_core_libs})

  # Check codegen libs and add needed libraries.
  set(llvm_extra ${MSPAL_llvm_extra_libs_${llvm_codegen_libs}})
  if("${llvm_extra}" STREQUAL "" AND NOT "${TARGET_ARCH}" STREQUAL "wasm")
    message(FATAL_ERROR "FIXME: ${TARGET_ARCH}")
  endif()

  set(llvm_libs ${llvm_core_libs} ${llvm_extra})
  list(TRANSFORM llvm_libs PREPEND "${LLVM_PREFIX}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}")
  list(TRANSFORM llvm_libs APPEND "${CMAKE_STATIC_LIBRARY_SUFFIX}")

  if (${llvm_api_version} LESS 1100)
    message(FATAL_ERROR "LLVM version too old.")
  endif()

  set(ENABLE_LLVM 1)
  set(ENABLE_LLVM_RUNTIME 1)
  set(LLVM_LIBS ${llvm_libs} ${llvm_system_libs})
  set(LLVM_LIBDIR "${LLVM_PREFIX}/lib")
  set(LLVM_INCLUDEDIR "${llvm_includedir}")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${llvm_cflags}")
  if(HOST_WIN32)
    # /EHsc already enabled, prevent LLVM flags to disable it. Corresponds to -fexceptions.
    string(REPLACE "/EHs-c-" "" llvm_cxxflags "${llvm_cxxflags}")
    # /GR- already enabled and inherited from LLVM flags. Corresponds to -fno-rtti.
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${llvm_cxxflags}")
  elseif(HOST_BROWSER)
    # emscripten's handling of the different exception modes is complex, so having multiple flags
    # passed during a single compile is undesirable. we need to set them elsewhere.
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${llvm_cxxflags} -fno-rtti")
  else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${llvm_cxxflags} -fexceptions -fno-rtti")
  endif()
  add_definitions(-DLLVM_API_VERSION=${llvm_api_version})
endif()

######################################
# ICU CHECKS
######################################
if(HOST_OSX OR HOST_MACCAT OR HOST_IOS OR HOST_TVOS)
  # FIXME: Handle errors
  execute_process(COMMAND  brew --prefix OUTPUT_VARIABLE brew_prefix OUTPUT_STRIP_TRAILING_WHITESPACE)

  if((HOST_MACCAT OR HOST_IOS OR HOST_TVOS) AND "${CMAKE_SHARED_LINKER_FLAGS}" MATCHES "${brew_prefix}/opt/icu4c/lib")
    message(FATAL_ERROR "Linker flags contain the Homebrew version of ICU which conflicts with the iOS/tvOS/MacCatalyst version: ${CMAKE_SHARED_LINKER_FLAGS}")
  endif()
endif()

if(MSPAL_CROSS_COMPILE)
elseif(HOST_OSX AND NOT HOST_MACCAT)
  include(FindPkgConfig)
  set(ENV{PKG_CONFIG_PATH} "{$PKG_CONFIG_PATH}:${brew_prefix}/lib/pkgconfig:${brew_prefix}/opt/icu4c/lib/pkgconfig")
  # Defines ICU_INCLUDEDIR/ICU_LIBDIR
  pkg_check_modules(ICU icu-uc)
  set(OSX_ICU_LIBRARY_PATH /usr/lib/libicucore.dylib)
  set(ICU_FLAGS "-DTARGET_UNIX -DU_DISABLE_RENAMING -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option -Wno-deprecated-declarations")
  set(HAVE_SYS_ICU 1)
elseif(HOST_WASI)
  set(ICU_FLAGS "-DPALEXPORT=\"\" -DU_DISABLE_RENAMING -DHAVE_UDAT_STANDALONE_SHORTER_WEEKDAYS -DHAVE_SET_MAX_VARIABLE -DTARGET_UNIX -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option")
  set(HAVE_SYS_ICU 1)
  set(STATIC_ICU 1)
  set(ICU_LIBS "icucore")
elseif(HOST_BROWSER)
  set(ICU_FLAGS "-DPALEXPORT=\"\" -DU_DISABLE_RENAMING -DHAVE_UDAT_STANDALONE_SHORTER_WEEKDAYS -DHAVE_SET_MAX_VARIABLE -DTARGET_UNIX -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option")
  set(HAVE_SYS_ICU 1)
  set(STATIC_ICU 1)
  set(ICU_LIBS "icucore")
elseif(HOST_IOS OR HOST_TVOS OR HOST_MACCAT)
  set(ICU_FLAGS "-DTARGET_UNIX -DU_DISABLE_RENAMING -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option -Wno-deprecated-declarations")
  set(HAVE_SYS_ICU 1)
  set(STATIC_ICU 1)
  set(ICU_LIBS icuuc icui18n icudata)
elseif(HOST_ANDROID)
  set(ICU_FLAGS "-DPALEXPORT=\"\" -DHAVE_UDAT_STANDALONE_SHORTER_WEEKDAYS -DHAVE_SET_MAX_VARIABLE -DTARGET_UNIX -DTARGET_ANDROID -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option")
  set(HAVE_SYS_ICU 1)
elseif(HOST_LINUX)
  include(FindPkgConfig)
  if(CROSS_ROOTFS)
    set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CROSS_ROOTFS}")
  endif(CROSS_ROOTFS)
  pkg_check_modules(ICU icu-uc)
  set(ICU_FLAGS "-DTARGET_UNIX -DU_DISABLE_RENAMING -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option -Wno-deprecated-declarations")
  set(HAVE_SYS_ICU 1)
elseif(HOST_WIN32)
  set(ICU_FLAGS "-DTARGET_WINDOWS -DPALEXPORT=EXTERN_C")
  set(HAVE_SYS_ICU 1)
elseif(HOST_SOLARIS)
  set(ICU_FLAGS "-DPALEXPORT=\"\" -DTARGET_UNIX -Wno-reserved-id-macro -Wno-documentation -Wno-documentation-unknown-command -Wno-switch-enum -Wno-covered-switch-default -Wno-extra-semi-stmt -Wno-unknown-warning-option")
  set(HAVE_SYS_ICU 1)
elseif(TARGET_FREEBSD)
  set(ICU_FLAGS "-DTARGET_UNIX -Wno-deprecated-declarations")
  set(HAVE_SYS_ICU 1)
  set(ICU_INCLUDEDIR "${CROSS_ROOTFS}/usr/local/include")
  set(ICU_LIBDIR "${CROSS_ROOTFS}/usr/local/lib")
else()
  message(FATAL_ERROR "Unknown host")
endif()

######################################
# CHECKED BUILD CHECKS
######################################
function(process_checked_build)
  string(REPLACE "," ";" tmp1 "${CHECKED_BUILD}")
  foreach(arg ${tmp1})
    string(TOUPPER "${arg}" var1)
    set(ENABLE_CHECKED_BUILD_${var1} 1 PARENT_SCOPE)
  endforeach(arg)
endfunction()

if(CHECKED_BUILD)
  set(ENABLE_CHECKED_BUILD 1)
  process_checked_build()
elseif (CMAKE_BUILD_TYPE STREQUAL "Debug")
  # if no explicit -DCHECKED_BUILD=args option and we're building debug, just do ENABLE_CHECKED_BUILD_PRIVATE_TYPES
  set(ENABLE_CHECKED_BUILD 1)
  set(ENABLE_CHECKED_BUILD_PRIVATE_TYPES 1)
endif()
### End of checked build checks

######################################
# OS SPECIFIC CHECKS
######################################

if(CLR_CMAKE_HOST_ALPINE_LINUX)
  # Setting RLIMIT_NOFILE breaks debugging of coreclr on Alpine Linux for some reason
  add_definitions(-DDONT_SET_RLIMIT_NOFILE)
  # On Alpine Linux, we need to ensure that the reported stack range for the primary thread is
  # larger than the initial committed stack size.
  add_definitions(-DENSURE_PRIMARY_STACK_SIZE)
endif()

if(CLR_CMAKE_HOST_APPLE)
  # TODO: this is already set by configurecompiler.cmake, remove this once mono uses that
  check_c_compiler_flag(-fno-objc-msgsend-selector-stubs COMPILER_SUPPORTS_FNO_OBJC_MSGSEND_SELECTOR_STUBS)
  if(COMPILER_SUPPORTS_FNO_OBJC_MSGSEND_SELECTOR_STUBS)
    set(CLR_CMAKE_COMMON_OBJC_FLAGS "${CLR_CMAKE_COMMON_OBJC_FLAGS} -fno-objc-msgsend-selector-stubs")
  endif()
endif()

### End of OS specific checks
