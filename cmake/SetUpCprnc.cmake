
INCLUDE(ExternalProject)


# CPRNC locations
SET (CPRNC_INSTALL_DIR ${CMAKE_BINARY_DIR}/utils/cprnc)
SET (CPRNC_BINARY ${CMAKE_BINARY_DIR}/utils/cprnc/bin/cprnc)

# Always remove this directory when configuring
#   this is the only way to ensure that the cprnc cache is deleted
FILE(REMOVE_RECURSE ${CPRNC_INSTALL_DIR})

# The following builds cprnc 
ExternalProject_Add(
  cprnc
  SOURCE_DIR ${CMAKE_SOURCE_DIR}/utils/cprnc_130319
  CMAKE_ARGS
    -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DCMAKE_Fortran_FLAGS='${CMAKE_Fortran_FLAGS}'
    -DCMAKE_C_FLAGS='${CMAKE_C_FLAGS}'
    -DNETCDF_DIR=${CPRNC_NETCDF_DIR}
    -DHDF5_DIR=${CPRNC_HDF5_DIR}
    -DSZIP_DIR=${CPRNC_SZIP_DIR}
    -DZLIB_DIR=${CPRNC_ZLIB_DIR}
    -DCURL_DIR=${CPRNC_CURL_DIR}
    -DCMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
    -DCMAKE_INSTALL_PREFIX=${CPRNC_INSTALL_DIR}
  INSTALL_DIR ${CPRNC_INSTALL_DIR}
  PREFIX ${CPRNC_INSTALL_DIR}
  LOG_CONFIGURE ON)



