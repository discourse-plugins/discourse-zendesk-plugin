# frozen_string_literal: true

require 'rails_helper'
RSpec.describe 'Discourse Zendesk Plugin' do
  let(:staff) { Fabricate(:moderator) }
  let(:zendesk_url_default) { 'https://your-url.zendesk.com/api/v2' }
  let(:zendesk_api_ticket_url) { zendesk_url_default + '/tickets' }

  let(:ticket_response) do
    {
      ticket: {
        id: 'ticket_id',
        url: 'ticket_url'
      }
    }.to_json
  end

  before do
    default_header = { 'Content-Type' => 'application/json; charset=UTF-8' }
    stub_request(:post, zendesk_api_ticket_url).
      to_return(status: 200, body: ticket_response, headers: default_header)
    stub_request(:get, zendesk_url_default + "/users/me").
      to_return(status: 200, body: { user: {} }.to_json, headers: default_header)
  end

  describe 'Plugin Settings' do
    describe 'Storage Preparation' do
      let(:zendesk_enabled_default) { false }

      it 'has zendesk_url & zendesk_enabled site settings' do
        expect(SiteSetting.zendesk_url).to eq(zendesk_url_default)
        expect(SiteSetting.zendesk_enabled).to eq(zendesk_enabled_default)
      end
    end
  end

  describe 'Zendesk Integration' do
    describe 'Create ticket' do
      let!(:topic) { Fabricate(:topic) }
      let!(:p1) { Fabricate(:post, topic: topic) }
      let(:zendesk_api_user_search_url) { zendesk_url_default + "/users/search?query=#{p1.user.email}" }
      let(:zendesk_api_user_create_url) { zendesk_url_default + "/users" }

      before do
        sign_in staff
        default_header = { 'Content-Type' => 'application/json; charset=UTF-8' }
        stub_request(:get, zendesk_api_user_search_url).
          to_return(status: 200, body: { user: {} }.to_json, headers: default_header)
        stub_request(:post, zendesk_api_user_create_url).
          to_return(status: 200, body: { user: { id: 24 } }.to_json, headers: default_header)
      end

      it 'creates a new zendesk ticket' do
        post '/zendesk-plugin/issues.json', params: {
          topic_id: topic.id
        }

        expect(WebMock).to have_requested(:post, zendesk_api_ticket_url).with { |req|
          body = JSON.parse(req.body)
          body['ticket']['submitter_id'] == 24 &&
          body['ticket']['priority'] == 'normal' &&
          body['ticket']['custom_fields'].find { |field|
            field['imported_from'].present? && field['external_id'].present? &&
            field['imported_by'] == 'discourse_zendesk_plugin'
          }
        }

        expect(topic.custom_fields['discourse_zendesk_plugin_zendesk_api_url']).to eq('ticket_url')
        expect(topic.custom_fields['discourse_zendesk_plugin_zendesk_id']).to eq('ticket_id')
      end
    end
  end
end
