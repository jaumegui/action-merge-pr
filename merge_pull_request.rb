require 'httparty'
require 'json'

module Notion
  class Note
    def initialize(json_page)
      raise 'Not a page' unless json_page['object'] == 'page'

      @json_page = json_page
    end

    def id
      @json_page['id']
    end

    def title
      @json_page['properties']['Description']['title'].first['plain_text']
    end

    def priority
      @json_page['properties']['Priority']['select']['name']
    end

    def url
      @json_page['url']
    end

    def status
      @json_page['properties']['Statut Tech']['select']['name']
    end
  end

  class Client
    include HTTParty
    base_uri 'https://api.notion.com/v1/'

    def get_page(page_id)
      request(:get, "/pages/#{page_id}")
    end

    def query_database(query)
      request(:post, "/databases/#{database_id}/query", query)
    end

    def update_page(page_id, properties)
      request(:patch, "/pages/#{page_id}", properties)
    end

    def retrieve_database(body = nil)
      request(:get, "/databases/#{database_id}", body)
    end

    private

    def request(method_name, path, body = nil)
      options = { headers: headers, format: :plain }
      options.merge!(body: body.to_json) if body

      response = self.class.public_send(method_name, path, options)

      JSON.parse response
    end

    def database_id
      ENV['NOTION_DATABASE_ID']
    end

    def headers
      {
        'Authorization' => "Bearer #{ENV['NOTION_SECRET']}",
        'Notion-Version' => '2022-06-28',
        'Content-Type' => 'application/json'
      }
    end
  end

  class Wrapper
    attr_reader :client

    def initialize
      @client = Notion::Client.new
    end

    def get_page(page_id)
      client.get_page(page_id)
    end

    def get_database(database_id)
      client.retrieve_database(database_id)
    end

    def get_page_by_branch_id(branch_id)
      body = {
        filter: {
          property: 'Branch identifier',
          formula: {
            string: {
              equals: branch_id
            }
          }
        }
      }

      json_page = client.query_database(body)['results'].first
      Notion::Note.new(json_page)
    end

    def set_pr_ull(note_id)
      properties = {
        "Pr Github" => {
          "url" => ENV['PR_URL']
        }
      }

      client.update_page(note_id, { properties: properties })
    end

    def set_in_progress(note_id)
      properties = {
        "Statut Tech" => {
          "select" => {
            "name" => "2 - In progress"
          }
        }
      }

      client.update_page(note_id, { properties: properties })
    end

    def set_shipped(note_id)
      properties = {
        "Statut Tech" => {
          "select" => {
            "name" => "5 - Shipped"
          }
        }
      }

      client.update_page(note_id, { properties: properties })
    end
  end
end

class MergePullRequest
  attr_accessor :branch_id

  def perform(branch_name)
    self.branch_id = branch_name.split('-').last
    note = wrapper.get_page_by_branch_id(branch_id)

    if note
      wrapper.set_shipped(note.id)
    end
  end

  private

  def note
    @note ||= wrapper.get_page_by_branch_id(branch_id)
  end

  def wrapper
    @wrapper ||= Notion::Wrapper.new
  end
end

MergePullRequest.new.perform(ENV['BRANCH_NAME'])
