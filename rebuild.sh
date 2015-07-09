cd libuv; sh autogen.sh; ./configure; make
rm .libs/lib*.so*
rm .libs/lib*.dylib
cd ../luajit; make
rm src/lib*.so*
rm src/lib*.dylib
cd ..
make clean
premake5 clean
premake5 gmake
make

