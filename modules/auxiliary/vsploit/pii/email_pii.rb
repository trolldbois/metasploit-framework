##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#   http://metasploit.com/
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary

	#
	# This module sends pii via an attacker smtp machine
	#
	include Msf::Exploit::Remote::SMTPDeliver
	include Msf::Auxiliary::PII

	def initialize(info = {})
		super(update_info(info,
			'Name'           => 'VSploit Email PII',
			'Description'    => %q{
					This auxiliary reads from a file and sends data which
			should be flagged via an internal or external SMTP server.
			},
			'License'        => MSF_LICENSE,
			'Author'         =>  ['willis'],
			'Version'        => '$Revision$'
		))
			register_options(
				[
					OptString.new('RHOST', [true, "SMTP server address",'127.0.0.1']),
					OptString.new('RPORT', [true, "SMTP server port",'25'])
				], self.class)
	end

	def run

		msg = Rex::MIME::Message.new
		msg.mime_defaults
		msg.subject = datastore['SUBJECT']
		msg.to = datastore['MAILTO']
		msg.from = datastore['MAILFROM']

		data = create_pii

		msg.add_part(data, "text/plain")
		msg.add_part_attachment(data, rand_text_english(10))

		resp = send_message(msg.to_s)
	end
end
