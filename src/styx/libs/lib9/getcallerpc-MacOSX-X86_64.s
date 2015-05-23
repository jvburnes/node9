#
# this returns the next instruction (return address) of the caller of the 
# function that getcallerpc is called from.  in other words it yields
# the return address of the caller of the current function.
# 
# since the SYSV X86_64 calling conventions place the return address
# in a location that's very difficult to predict without additional debug
# information, we're stubbing this out until further information about
# the necessity of this information in the memory allocation tag is 
# available.
#
# Until then this code just returns 0.   
#
# NOTE: In theory, if not in debug mode, the location of the caller
# return address can be computed by the following algorithm.
# 
# Since getcallerpc is only called from the memory allocation routines
# and since it always refers to the stack frame of the caller...
# 
# IFF the user of getcallerpc passes the total size of the arguments
# passed to the current function 'S', then getcallerpc can back into
# the return address.
#
# 1. getcallerpc itself receives a single void*.  In 64 bit mode that
#    argument is passed in the RDI register. In X86_64 SYSV convention
#    the first 6 arguments are passed in the 6 primary GP registers.
#    The return address appears on the top of the stack, unless an
#    optional 7th argument is pushed over it.  In that case the
#    7th argument is on the top of the stack and the return address
#    is just below it.
#
# so...
#
#    First we compute the address of the top of the stack of the 
#    previous stack frame.  Since there's only one 64-bit word
#    on our stack frame (our return address), we subtract one word. Then...
#
#    Rather than passing the address of the first argument to getcallerpc
#    we pass the total size (in bytes) of the arguments passed.  This allows
#    us to compute the location of the return address in the following way
# 
#    Number of registers_used = total_size / 8;
#    Since there are only 6 available GP registers and a maximum of 7
#    arguments, subtract 6 from registers_used = excess.  If excess <= 0
#    the PC (return address) will be on the top of the stack.  Otherwise
#    add the excess offset to the top of the stack to find the location of
#    the PC return address.
#
#    In theory...
#    If not in debug mode...
#    On X86_64...
#    In the night...
#
#    We're passing 0 back until we're sure
#
	.file	"getcallerpc-MacOSX-X86_64.s"
    .text
.globl _getcallerpc
_getcallerpc:
	movq	$0, %rax
	ret
