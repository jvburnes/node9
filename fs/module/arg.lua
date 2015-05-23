-- arg.lua: this is similar to, but a higher level version of the limbo 'arg' module.
-- while it supports various low-level interfaces such as setusage and progname
-- it does not implement arg and opt, rather it performs the high-level processing
-- needed to create an option/value map accoring to the POSIX getopt interface
-- as follows: getopt(arg, options)
--    param:   'arg' contains the command line arguments in an array-like table.
--    param:   'options' is a string with the letters that expect string values.
--    returns: a hash-like table where associated option keys are true, nil, 
--             or a string value.
-- The following example styles are supported
--   -a one  ==> opts["a"]=="one"
--   -bone   ==> opts["b"]=="one"
--   -c      ==> opts["c"]==true
--   --c=one ==> opts["c"]=="one"
--   -cdaone ==> opts["c"]==true opts["d"]==true opts["a"]=="one"
--
-- (note) POSIX demands the parser ends at the first non option
--      this behavior isn't implemented.
--
-- this module obeys the lua POSIX interface, which means that an app 
-- argument list contains the following:
--   arg[0] = full path of program name
--   arg[1-n] = arguments in order
--   arg[-1] = name of executable interpreting arg[0] (not currently used)
--

name = ""
usagemsg = ""
printusage = true
args = {}

sys = import('sys')

function argv()
    local arglist = {}
    for i=1,#args do arglist[i] = args[i] end
    return arglist
end
        
-- strips the options and returns only the argument words
function strip(...)
    local ain = {...}
    local iargs = args or ain[1]
    
    local anum = 0
    local sargs = {}
    for i,v in ipairs(iargs) do
        if v:sub(1,1) ~= '-' then
            anum = anum + 1
            sargs[anum] = v
        end
    end
    return sargs
end

function setusage(u)
	usagemsg = u
	printusage = u ~= nil
end

function progname()
	return name
end

function usage()
    local u
	if printusage then 
		if usagemsg ~= nil then
			u = "usage: " .. usagemsg
		else
			u = name + ": argument expected"
        end
		sys.fprint(sys.fildes(2), "%s\n", u);
	end
	error("fail:usage")
end

-- returns an option/value map according to POSIX "getopt" and saves the arg list
function getopt(arg, options)
  if type(arg) ~= "table" then error("arg.getopt(argv,options): argv is not a table",2) end
  if type(options) ~= "string" then error("arg.getopt(argv,options): options is not a string",2) end
  
  name = table.remove(arg,1)
  args = arg
  local tab = {}
  for k, v in ipairs(arg) do
    if string.sub( v, 1, 2) == "--" then
      local x = string.find( v, "=", 1, true )
      if x then
          tab[ string.sub( v, 3, x-1 ) ] = string.sub( v, x+1 )
      else
          tab[ string.sub( v, 3 ) ] = true
      end
    elseif string.sub( v, 1, 1 ) == "-" then
      local y = 2
      local l = string.len(v)
      local jopt
      while ( y <= l ) do
        jopt = string.sub( v, y, y )
        if string.find( options, jopt, 1, true ) then
          if y < l then
            tab[ jopt ] = string.sub( v, y+1 )
            y = l
          else
            tab[ jopt ] = arg[ k + 1 ]
          end
        else
          tab[ jopt ] = true
        end
        y = y + 1
      end
    end
  end
  return tab
end

