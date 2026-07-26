# frozen_string_literal: true

require_relative "app_store_connect_client"

# 1回のGitHub Actionsビルドを外部TestFlight配信へ進める処理を担当します。
class TestFlightBuildPublisher
  REQUIRED_PLATFORMS = %w[IOS MAC_OS].freeze
  PROCESSING_STATE = "PROCESSING"
  VALID_STATE = "VALID"
  READY_FOR_REVIEW_STATE = "READY_FOR_BETA_SUBMISSION"
  REVIEW_IN_PROGRESS_OR_COMPLETE_STATES = %w[
    WAITING_FOR_BETA_REVIEW
    IN_BETA_REVIEW
    APPROVED
    IN_BETA_TESTING
  ].freeze
  REVIEW_CONTACT_FIELDS = %w[
    contactFirstName
    contactLastName
    contactPhone
    contactEmail
  ].freeze

  def initialize(client:, app_id:, beta_group_id:, build_number:, attempts: 60, interval_seconds: 15, sleeper: Kernel)
    @client = client
    @app_id = app_id
    @beta_group_id = beta_group_id
    @build_number = build_number
    @attempts = attempts
    @interval_seconds = interval_seconds
    @sleeper = sleeper
  end

  def publish(submit_external_review:)
    builds = wait_for_valid_builds
    add_builds_to_beta_group(builds)
    puts "Added iOS and native macOS build #{@build_number} to the TestFlight beta group."

    return unless submit_external_review

    validate_review_contact
    submit_builds_for_external_review(builds)
    puts "Submitted eligible iOS and native macOS builds for external TestFlight review."
  end

  private

  def wait_for_valid_builds
    @attempts.times do |attempt|
      builds = builds_by_platform
      invalid = builds.find do |_platform, build|
        ![PROCESSING_STATE, VALID_STATE].include?(build.dig("attributes", "processingState"))
      end
      raise "Build processing failed for #{invalid.first}." if invalid

      if REQUIRED_PLATFORMS.all? { |platform| builds.dig(platform, "attributes", "processingState") == VALID_STATE }
        return builds
      end

      puts "Waiting for App Store Connect to process build #{@build_number} (attempt #{attempt + 1}/#{@attempts})."
      @sleeper.sleep(@interval_seconds) if attempt + 1 < @attempts
    end

    raise "Timed out waiting for valid iOS and native macOS build #{@build_number}."
  end

  def builds_by_platform
    response = @client.get(
      "/v1/builds",
      query: {
        "filter[app]" => @app_id,
        "filter[version]" => @build_number,
        "include" => "preReleaseVersion",
        "limit" => "20"
      }
    )
    versions = Array(response["included"]).to_h { |version| [version["id"], version.dig("attributes", "platform")] }

    Array(response["data"]).each_with_object({}) do |build, result|
      version_id = build.dig("relationships", "preReleaseVersion", "data", "id")
      platform = versions[version_id]
      result[platform] = build if REQUIRED_PLATFORMS.include?(platform)
    end
  end

  def add_builds_to_beta_group(builds)
    relationship_data = REQUIRED_PLATFORMS.map { |platform| { type: "builds", id: builds.fetch(platform).fetch("id") } }
    @client.post(
      "/v1/betaGroups/#{@beta_group_id}/relationships/builds",
      body: { data: relationship_data }
    )
  end

  def validate_review_contact
    response = @client.get("/v1/apps/#{@app_id}/betaAppReviewDetail")
    attributes = response.fetch("data").fetch("attributes")
    missing = REVIEW_CONTACT_FIELDS.select { |field| attributes[field].to_s.strip.empty? }
    return if missing.empty?

    raise "External TestFlight review contact is incomplete in App Store Connect: #{missing.join(', ')}"
  end

  def submit_builds_for_external_review(builds)
    REQUIRED_PLATFORMS.each do |platform|
      build_id = builds.fetch(platform).fetch("id")
      detail = @client.get("/v1/builds/#{build_id}/buildBetaDetail")
      state = detail.dig("data", "attributes", "externalBuildState")
      next if REVIEW_IN_PROGRESS_OR_COMPLETE_STATES.include?(state)

      unless state == READY_FOR_REVIEW_STATE
        raise "Build #{build_id} cannot be submitted for external review from state #{state.inspect}."
      end

      @client.post(
        "/v1/betaAppReviewSubmissions",
        body: {
          data: {
            type: "betaAppReviewSubmissions",
            relationships: { build: { data: { type: "builds", id: build_id } } }
          }
        }
      )
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    required_environment = %w[
      ASC_API_KEY_ID
      ASC_API_ISSUER_ID
      ASC_API_PRIVATE_KEY_PATH
      ASC_APP_ID
      ASC_BETA_GROUP_ID
      ASC_BUILD_NUMBER
    ]
    missing_environment = required_environment.select { |name| ENV[name].to_s.empty? }
    abort "Missing required environment variables: #{missing_environment.join(', ')}" unless missing_environment.empty?

    client = AppStoreConnectClient.new(
      key_id: ENV.fetch("ASC_API_KEY_ID"),
      issuer_id: ENV.fetch("ASC_API_ISSUER_ID"),
      private_key_path: ENV.fetch("ASC_API_PRIVATE_KEY_PATH")
    )
    publisher = TestFlightBuildPublisher.new(
      client: client,
      app_id: ENV.fetch("ASC_APP_ID"),
      beta_group_id: ENV.fetch("ASC_BETA_GROUP_ID"),
      build_number: ENV.fetch("ASC_BUILD_NUMBER"),
      attempts: ENV.fetch("ASC_PROCESSING_ATTEMPTS", "60").to_i,
      interval_seconds: ENV.fetch("ASC_PROCESSING_INTERVAL_SECONDS", "15").to_i
    )
    publisher.publish(submit_external_review: ENV.fetch("ASC_SUBMIT_EXTERNAL_REVIEW", "false") == "true")
  rescue StandardError => error
    abort error.message
  end
end
