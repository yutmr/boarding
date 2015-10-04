class InviteController < ApplicationController
  before_action :set_app_details
  before_action :check_disabled_text

  def index
    if user and password
      # default
    else
      render 'environment_error'
    end
  end

  def submit
    if @message # from a `before_action`
      render :index
      return
    end

    email = params[:email]
    first_name = params[:first_name]
    last_name = params[:last_name]

    if ENV["ITC_TOKEN"]
      if ENV["ITC_TOKEN"] != params[:token]
        @message = "Invalid password given, please contact the application owner"
        @type = "danger"
        render :index
        return
      end
    end

    if email.length == 0
      render :index
      return
    end

    if ENV["ITC_IS_DEMO"]
      @message = "This is a demo page. Here would be the success message with information about the TestFlight email"
      @type = "success"
      render :index
      return
    end

    logger.info "Going to create a new tester: #{email} - #{first_name} #{last_name}"

    begin
      login

      tester = Spaceship::Tunes::Tester::Internal.find(email)
      tester ||= Spaceship::Tunes::Tester::External.find(email)
      # tester = Spaceship::Tunes::Tester::Internal.find(config[:email])
      # tester ||= Spaceship::Tunes::Tester::External.find(config[:email])
      # Helper.log.info "Existing tester #{tester.email}".green if tester

      tester ||= Spaceship::Tunes::Tester::External.create!(email: email, 
                                                            first_name: first_name, 
                                                            last_name: last_name)

      logger.info "Successfully created tester #{tester.email}"

      if apple_id.length > 0
        logger.info "Addding tester to application"
        tester.add_to_app!(apple_id)
        logger.info "Done"
      end

      if testing_is_live?
        @message = t('check_your_email_inbox_for_an_invite')
      else
        @message = t('you_will_be_notified_once_the_next_build_is_available')
      end
      @type = "success"
    rescue => ex
      if ex.inspect.to_s.include?"EmailExists"
        @message = t('email_address_is_already_registered')
        @type = "danger"
      else
        Rails.logger.fatal ex.inspect
        Rails.logger.fatal ex.backtrace.join("\n")

        @message = t('something_went_wrong')
        @type = "danger"
      end
    end

    render :index
  end

  private
    def user
      ENV["ITC_USER"] || ENV["FASTLANE_USER"]
    end

    def password
      ENV["ITC_PASSWORD"] || ENV["FASTLANE_PASSWORD"]
    end

    def apple_id
      Rails.logger.error "No app to add this tester to provided, use the `ITC_APP_ID` environment variable" unless ENV["ITC_APP_ID"]
      
      Rails.cache.fetch('AppID', expires_in: 10.minutes) do
        if ENV["ITC_APP_ID"].include?"." # app identifier
          login
          app = Spaceship::Application.find(ENV["ITC_APP_ID"])
          app.apple_id
        else
          ENV["ITC_APP_ID"].to_s
        end
      end
    end

    def app
      login

      @app ||= Spaceship::Tunes::Application.find(ENV["ITC_APP_ID"])

      raise "Could not find app with ID #{apple_id}" unless @app

      @app
    end

    def app_metadata
      Rails.cache.fetch('appMetadata', expires_in: 10.minutes) do
        {
          icon_url: app.app_icon_preview_url,
          title: app.name
        }
      end
    end

    def login
      return if @spaceship
      @spaceship = Spaceship::Tunes.login(user, password)
    end

    def set_app_details
      @metadata = app_metadata
      @title = @metadata[:title]
    end

    def check_disabled_text
      if ENV["ITC_CLOSED_TEXT"]
        @message = ENV["ITC_CLOSED_TEXT"]
        @type = "warning"
      end
    end

    # @return [Boolean] Is at least one TestFlight beta testing build available?
    def testing_is_live?
      app.build_trains.each do |version, train|
        if train.external_testing_enabled
          train.builds.each do |build|
            return true if build.external_testing_enabled
          end
        end
      end
      return false
    end
end
