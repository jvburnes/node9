cd libuv; sh autogen.sh; ./configure; make
rm .libs/lib*.so*
cd ../luajit; make
rm src/lib*.so*
cd ..
make clean
premake5 clean
premake5 gmake
make

