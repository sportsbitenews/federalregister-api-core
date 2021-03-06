class RegulatoryPlan < ApplicationModel
  class Contact
    def initialize(node)
      @node = node
    end
    
    SINGLE_VALUE_METHODS_TO_CSS = {
      :first_name                               => 'FIRST_NAME',
      :last_name                                => 'LAST_NAME',
      :title                                    => 'TITLE',
      :agency_name                              => 'AGENCY NAME',
      :phone                                    => 'PHONE',
      :fax                                      => 'FAX',
      :email                                    => 'EMAIL',
      :street_address                           => 'STREET_ADDRESS',
      :city                                     => 'CITY',
      :state                                    => 'STATE',
      :zip                                      => 'ZIP',
    }

    SINGLE_VALUE_METHODS_TO_CSS.each do |method, selector|
      define_method method do 
        @node.css(selector).first.try(:content)
      end
    end
  end
  
  extend ActiveSupport::Memoizable
  
  SIGNIFICANT_PRIORITY_CATEGORIES = ['Economically Significant', 'Other Significant']
  
  file_attribute(:full_xml)  {"#{RAILS_ROOT}/data/regulatory_plans/xml/#{issue}/#{regulation_id_number}.xml"}
  
  has_many :events,
           :class_name => "RegulatoryPlanEvent"
  has_many :entry_regulation_id_numbers,
           :primary_key => :regulation_id_number,
           :foreign_key => :regulation_id_number
  
  has_many :agency_name_assignments, :as => :assignable, :dependent => :destroy
  has_many :agency_names, :through => :agency_name_assignments
  
  has_many :agency_assignments, :as => :assignable
  has_many :agencies, :through => :agency_assignments, :extend => Agency::AssociationExtensions
  has_and_belongs_to_many :small_entities
  
  def entries
    Entry.with_regulation_id_number(self.regulation_id_number)
  end

  def find_by_regulation_id_number(rin)
    first(:conditions => {:regulation_id_number => rin}, :order => "issue DESC")
  end
  
  define_index do
    # Will require a index rebuild when new regulatory plan issue comes in...
    where "regulatory_plans.issue = '#{RegulatoryPlan.current_issue}'"
    
    # fields
    indexes title
    indexes abstract
    indexes "CONCAT('#{RAILS_ROOT}/data/regulatory_plans/', issue, '/', regulation_id_number, '.xml')", :as => :full_text, :file => true
    indexes priority_category, :facet => true
    
    # attributes
    has agency_assignments(:agency_id), :as => :agency_ids
    
    set_property :field_weights => {
      "title" => 100,
      "abstract" => 50,
      "full_text" => 25,
    }
    
    set_property :delta => ThinkingSphinx::Deltas::ManualDelta
  end
  # this line must appear after the define_index block
  include ThinkingSphinx::Deltas::ManualDelta::ActiveRecord
  
  def self.current_issue
    RegulatoryPlan.first(:select => :issue, :order => "issue DESC").try(:issue)
  end
  
  def self.in_current_issue
    scoped(:conditions => {:issue => current_issue})
  end
  
  def significant?
    RegulatoryPlan::SIGNIFICANT_PRIORITY_CATEGORIES.include?(priority_category)
  end
  
  def slug
    self.title.downcase.gsub(/&/, 'and').gsub(/[^a-z0-9]+/, '-').slice(0,100)
  end
  
  def source_url(format)
    format = format.to_sym
    
    case format
    when :html
      "http://www.reginfo.gov/public/do/eAgendaViewRule?pubId=#{issue}&RIN=#{regulation_id_number}"
    when :xml
      "http://www.reginfo.gov/public/do/eAgendaViewRule?pubId=#{issue}&RIN=#{regulation_id_number}&operation=OPERATION_EXPORT_XML"
    end
  end
  
  SINGLE_VALUE_METHODS_TO_CSS = {
    :statement_of_need                        => 'STMT_OF_NEED',
    :legal_basis                              => 'LEGAL_BASIS',
    :alternatives                             => 'ALTERNATIVES',
    :costs_and_benefits                       => 'COSTS_AND_BENEFITS',
    :risks                                    => 'RISKS',
    :major                                    => 'MAJOR',
    :regulatory_flexibility_analysis_required => 'RFA_REQUIRED',
    :energy_affected                          => 'ENERGY_AFFECTED',
    :international_interest                   => 'INTERNATIONAL_INTEREST',
  }

  SINGLE_VALUE_METHODS_TO_CSS.each do |method, selector|
    define_method method do 
      root_node.css(selector).first.try(:content)
    end
    memoize method
  end
  
  MULTI_VALUE_METHODS_TO_CSS = {
    :small_entities_affected                  => 'SMALL_ENTITY',
    :government_levels_affected               => 'GOVT_LEVEL',
    :cfr_citations                            => 'CFR',
    :legal_authorizations                     => 'LEGAL_AUTHORITY'
  }
  
  MULTI_VALUE_METHODS_TO_CSS.each do |method, selector|
    define_method method do 
      root_node.css(selector).map(&:content)
    end
    memoize method
  end
  
  def contacts
    root_node.css('CONTACT').map{|node| Contact.new(node)}
  end
  memoize :contacts
  
  private
  
  def root_node
    @root_node ||= Nokogiri::XML(full_xml).root
  end
  
  def simple_node_value(css_selector)
    root_node.css(css_selector).try(:content)
  end
  memoize :simple_node_value
  
end
