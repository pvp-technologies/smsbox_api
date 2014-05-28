module SmsboxApi
  class Sms < ActiveRecord::Base
    validates :number, :message, presence: true

    as_enum :direction, {
      incoming: 0,
      outgoing: 1
    }

    #Must be overriden by main app
    def self.is_allowed_number? number
      false
    end

    def self.send_sms number, message, mode = 'Standard', send_options = {}
      sms = SmsboxApi::Sms.create({
        direction: :outgoing,
        number: number,
        message: message,
        mode: mode
      })

      if sms
        request = HTTPI::Request.new("http://api.smsbox.fr/api.php")
        request.query = {
          login: SmsboxApi::Engine.smsbox_login,
          pass: SmsboxApi::Engine.smsbox_pass,
          dest: sms.number,
          msg: sms.message,
          mode: sms.mode,
          callback: "1",
          cvar: sms.id,
          id: "1"
        }

        #Real send ?
        if is_allowed_number? sms.number
          response = HTTPI.get(request, :net_http).body

          if response.index("OK")
            sms.api_response = "OK"
            sms.reference = response[3..-1]
            sms.save
            return true
          else
            sms.api_response = response
            sms.save
            return false
          end
        else
          sms.blacklisted
        end
      else
        return false
      end
    end

    def self.receive_ack params
      sms = SmsboxApi::Sms.where(
        number: params[:numero],
        reference: params[:reference]
      ).first

      if sms
        sms.ack = params[:accuse]
        sms.ack_time = Time.at(params[:ts].to_i)
        #Call ack_callback method (overriden by main application)
        sms.handle_ack
        sms.save
      else
        raise StandardError.new("Ack received for unknown sms #{params[:numero]} #{params[:reference]}")
      end
    end

    def self.receive_response params
      sms = SmsboxApi::Sms.create({
        direction: :incoming,
        number: params[:numero],
        reference: params[:reference],
        reception_time: Time.at(params[:ts].to_i),
        message: params[:message]
      })

      sms.handle_response
    end

    #Must be overriden by main app
    def handle_ack
      #NOTHING
    end

    #Must be overriden by main app
    def handle_response
      #NOTHING
    end

    #Must be overriden by main app
    def blacklisted
      #NOTHING
    end
  end
end