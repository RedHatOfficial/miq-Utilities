#
#
# Method name:  Email.rb
#
# Description:
# This method is intended to be included by other methods which need to send e-mails.
# It provides support for cc: and/or attachments which the built in does not.
#

# Encodage
# -*- coding: UTF-8 -*-


module RedHatConsulting_Utilities
  module StdLib
    module Email

      def initialize(handle = $evm)
        @handle = handle
      end

      def send_email(config = {})
        @debug = true
        # config hash should be defined as follows:
        # config = {}
        # config['to_email_address']    # from config or from default_config
        # config['cc_email_address']    # optional, from config or from default_config
        # config['from_email_address']  # from config or from default_config
        # config['signature']           # optional, from config or from default_config
        # config['subject']             # provide in config
        # config['body']                # provide in config
        # config['files']               # required for sending attachments only, should be an array of file paths, defaults to empty array.
        # config['delete_files']        # defaults to false, if true will remove files after sending

        log(:info, "config: #{config.inspect}") if @debug
        default_config = @handle.instance_find('/RedHatConsulting_Utilities/StdLib/Config/Email/Email')['Email'] || {}
        log(:info, "default_config: #{default_config.inspect}") if @debug

        config = default_config.merge(config)
        log(:info, "merged_config: #{config.inspect}") if @debug

        config['files'] = [] unless config.has_key?('files') && config['files'].is_a?(Array)
        config['delete_files'] = false unless config.has_key?('delete_files') && config['delete_files'] != true

        raise 'to_email_address not specified' if config['to_email_address'].blank?
        raise 'from_email_address not specified' if config['from_email_address'].blank?
        raise 'smtp_relay not specified' if config['smtp_relay'].blank?
        raise 'smtp_port not specified' if config['smtp_port'].blank?

        log(:info, "final config: #{config.inspect}") if @debug

        if config['signature'].present?
        config['body'] =<<EOF
#{config['body']}
<br><br>
Thanks,
<br>
#{config['signature']}
EOF
        end

        log(:info, "Sending email to <#{config['to_email_address']}> cc <#{config['cc_email_address']}> from <#{config['from_email_address']}> subject: <#{config['subject']}>")

        # Use net/smtp to be able send email with with cc and/or attachments.
        require 'net/smtp'

        marker = 'PART_SEPARATOR'
        message = ''
        # Define the main headers.
        part =<<EOF
Date: #{Time.now}
From: #{config['from_email_address']}
To: #{config['to_email_address']}
#{'Cc: ' + config['cc_email_address'] unless config['cc_email_address'].blank?} 
Subject:#{config['subject']} 
MIME-Version: 1.0
EOF
        message << part

        part =<<EOF
Content-Type: multipart/mixed; boundary=#{marker}
--#{marker}
Content-Type: text/html
Content-Transfer-Encoding:8bit
EOF
        message << part unless config['files'].empty?

        part =<<EOF
Content-Type: text/html; charset=UTF-8
EOF
        message << part if config['files'].empty?

        # Define the message action
        part =<<EOF

#{config['body']}
EOF

        message << part

        part =<<EOF
--#{marker}
EOF

        message << part unless config['files'].empty?

        config['files'].each do |file|
          # Read a file and encode it into base64 format
          filecontent = File.read(file)
          encodedcontent = [filecontent].pack('m')   # base64

          # Define the attachment section
          part = <<EOF
Content-Type: multipart/mixed; name=\"#{file}\"
Content-Transfer-Encoding:base64
Content-Disposition: attachment; filename="#{File.basename(file).gsub('.email_attachment_', '')}"

#{encodedcontent}
--#{marker}
EOF

          message << part
        end

        log(:info, "email message: #{message}")

        recipients = []
        recipients << config['to_email_address']
        recipients << config['cc_email_address'] unless config['cc_email_address'].blank?
        smtp = Net::SMTP.new(config['smtp_relay'],config['smtp_port'].to_i)
        smtp.enable_starttls_auto if smtp.respond_to?(:enable_starttls_auto)
        smtp.start(config['smtp_relay']) do |i|
          i.send_message message, config['from_email_address'], recipients
        end

        config['files'].each { |file| File.delete(file) if File.exist?(file) } unless config['files'].empty? || config['delete_files'] == false
      end

    end
  end
end
