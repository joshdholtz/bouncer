require_relative '../test_helper'

class TitoProviderTest < Minitest::Test
  CONFIG = {
    "slug"  => "my-conference",
    "year"  => "2027",
    "release_types" => {
      "stream"  => "Live Streaming",
      "speaker" => "Speaker"
    }
  }.freeze

  def setup
    ENV["TITO_SECRET"] = "test-secret"
  end

  # --- reference normalization ---

  def test_appends_dash_one_when_no_suffix
    stub_tito("ABCD-1", release_title: "General Admission")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    refute_nil result
  end

  def test_leaves_reference_unchanged_when_suffix_present
    stub_tito("ABCD-2", release_title: "General Admission")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD-2", config: CONFIG)
    refute_nil result
  end

  # --- type detection ---

  def test_returns_default_type_for_unmatched_release
    stub_tito("ABCD-1", release_title: "General Admission")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_equal :default, result.type
  end

  def test_returns_stream_type_for_matching_release
    stub_tito("ABCD-1", release_title: "Live Streaming Ticket")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_equal :stream, result.type
  end

  def test_type_matching_is_case_insensitive
    stub_tito("ABCD-1", release_title: "live streaming ticket")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_equal :stream, result.type
  end

  # --- speaker detection ---

  def test_is_speaker_false_for_non_speaker_ticket
    stub_tito("ABCD-1", release_title: "General Admission")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    refute result.extra[:is_speaker]
  end

  def test_is_speaker_true_for_speaker_ticket
    stub_tito("ABCD-1", release_title: "Speaker Ticket")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert result.extra[:is_speaker]
  end

  def test_speaker_ticket_keeps_default_type
    stub_tito("ABCD-1", release_title: "Speaker Ticket")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_equal :default, result.type
    assert result.extra[:is_speaker]
  end

  def test_speaker_and_stream_ticket_gets_stream_type_and_is_speaker
    stub_tito("ABCD-1", release_title: "Live Streaming Speaker Ticket")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_equal :stream, result.type
    assert result.extra[:is_speaker]
  end

  # --- not found / errors ---

  def test_returns_nil_when_no_ticket_matches_reference
    stub_tito_empty
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_nil result
  end

  def test_returns_nil_on_404
    stub_request(:get, /api\.tito\.io/).to_return(status: 404)
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_nil result
  end

  def test_returns_nil_on_401
    stub_request(:get, /api\.tito\.io/).to_return(status: 401, body: "Unauthorized")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_nil result
  end

  def test_returns_nil_on_server_error
    stub_request(:get, /api\.tito\.io/).to_return(status: 500, body: "Internal Server Error")
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_nil result
  end

  def test_returns_nil_on_network_error
    stub_request(:get, /api\.tito\.io/).to_raise(StandardError.new("connection refused"))
    result = Bouncer::Providers::Tito.verify("user@example.com", "ABCD", config: CONFIG)
    assert_nil result
  end

  private

  def stub_tito(reference, release_title:)
    body = {
      "tickets" => [
        {
          "reference" => reference,
          "release"   => { "title" => release_title }
        }
      ]
    }.to_json

    stub_request(:get, /api\.tito\.io/).to_return(
      status: 200,
      body: body,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_tito_empty
    stub_request(:get, /api\.tito\.io/).to_return(
      status: 200,
      body: { "tickets" => [] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end
end
