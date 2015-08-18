cd libuv; sh autogen.sh; ./configure; make
rm .libs/lib*.so*
rm .libs/lib*.dylib
cd ../luajit; make
rm src/lib*.so*
rm src/lib*.dylib
cd ..
#premake5 clean
rm -rf src/build
#rm *.make
#rm Makefile
premake5 gmake
make config=debug_macosx

