# frozen_string_literal: true

require "minitest/autorun"
require_relative "testflight_build_publisher"

class TestFlightBuildPublisherTest < Minitest::Test
  APP_ID = "app-id"
  GROUP_ID = "group-id"
  BUILD_NUMBER = "42"

  def test_publish_waits_for_ios_and_adds_only_it_to_group
    client = TestFlightPublisherFakeClient.new(
      build_responses: [builds_response(ios_state: "PROCESSING", mac_state: "PROCESSING"), builds_response]
    )
    publisher = publisher(client, attempts: 2)

    publisher.publish(submit_external_review: false)

    relationship = client.posts.fetch("/v1/betaGroups/#{GROUP_ID}/relationships/builds")
    assert_equal %w[ios-build], relationship.fetch(:data).map { |build| build.fetch(:id) }
  end

  def test_publish_reports_incomplete_review_contact_without_submitting
    client = TestFlightPublisherFakeClient.new(
      build_responses: [builds_response],
      review_contact: complete_review_contact.merge("contactPhone" => nil)
    )
    publisher = publisher(client)

    error = assert_raises(RuntimeError) { publisher.publish(submit_external_review: true) }

    assert_includes error.message, "contactPhone"
    refute client.posts.key?("/v1/betaAppReviewSubmissions")
  end

  def test_publish_stops_when_app_store_connect_rejects_the_ios_build
    client = TestFlightPublisherFakeClient.new(
      build_responses: [builds_response(ios_state: "INVALID")]
    )
    publisher = publisher(client)

    error = assert_raises(RuntimeError) { publisher.publish(submit_external_review: false) }

    assert_includes error.message, "IOS"
    refute client.posts.key?("/v1/betaGroups/#{GROUP_ID}/relationships/builds")
  end

  def test_publish_ignores_a_rejected_native_macos_build
    client = TestFlightPublisherFakeClient.new(
      build_responses: [builds_response(mac_state: "INVALID")]
    )
    publisher = publisher(client)

    publisher.publish(submit_external_review: false)

    relationship = client.posts.fetch("/v1/betaGroups/#{GROUP_ID}/relationships/builds")
    assert_equal %w[ios-build], relationship.fetch(:data).map { |build| build.fetch(:id) }
  end

  def test_publish_submits_ready_builds_for_external_review
    client = TestFlightPublisherFakeClient.new(
      build_responses: [builds_response],
      review_contact: complete_review_contact,
      external_states: { "ios-build" => "READY_FOR_BETA_SUBMISSION" }
    )
    publisher = publisher(client)

    publisher.publish(submit_external_review: true)

    submissions = client.post_history.select { |path, _body| path == "/v1/betaAppReviewSubmissions" }
    assert_equal 1, submissions.count
    assert_equal %w[ios-build], submissions.map { |_path, body| body.dig(:data, :relationships, :build, :data, :id) }
  end

  def test_publish_does_not_resubmit_builds_already_in_external_testing
    client = TestFlightPublisherFakeClient.new(
      build_responses: [builds_response],
      review_contact: complete_review_contact,
      external_states: { "ios-build" => "IN_BETA_TESTING" }
    )
    publisher = publisher(client)

    publisher.publish(submit_external_review: true)

    refute client.posts.key?("/v1/betaAppReviewSubmissions")
  end

  private

  def publisher(client, attempts: 1)
    TestFlightBuildPublisher.new(
      client: client,
      app_id: APP_ID,
      beta_group_id: GROUP_ID,
      build_number: BUILD_NUMBER,
      attempts: attempts,
      interval_seconds: 0
    )
  end

  def builds_response(ios_state: "VALID", mac_state: "VALID")
    {
      "data" => [build("ios-build", "ios-version", ios_state), build("mac-build", "mac-version", mac_state)],
      "included" => [pre_release_version("ios-version", "IOS"), pre_release_version("mac-version", "MAC_OS")]
    }
  end

  def build(id, version_id, state)
    {
      "id" => id,
      "attributes" => { "processingState" => state },
      "relationships" => { "preReleaseVersion" => { "data" => { "id" => version_id } } }
    }
  end

  def pre_release_version(id, platform)
    { "id" => id, "attributes" => { "platform" => platform } }
  end

  def complete_review_contact
    {
      "contactFirstName" => "Test",
      "contactLastName" => "Reviewer",
      "contactPhone" => "+81 00 0000 0000",
      "contactEmail" => "review@example.com"
    }
  end
end

class TestFlightPublisherFakeClient
  attr_reader :posts, :post_history

  def initialize(build_responses:, review_contact: {}, external_states: {})
    @build_responses = build_responses
    @review_contact = review_contact
    @external_states = external_states
    @posts = {}
    @post_history = []
  end

  def get(path, query: {})
    return @build_responses.shift if path == "/v1/builds"
    return { "data" => { "attributes" => @review_contact } } if path.end_with?("/betaAppReviewDetail")

    build_id = path.split("/")[-2]
    { "data" => { "attributes" => { "externalBuildState" => @external_states.fetch(build_id) } } }
  end

  def post(path, body:)
    @posts[path] = body
    @post_history << [path, body]
    nil
  end
end
