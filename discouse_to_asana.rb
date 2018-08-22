require 'discourse_api'
require 'json'
require 'time'
require 'yaml/store'
require 'asana'
require 'jq'

class DiscourseQuestions
	def initialize
		@discourse_client = DiscourseApi::Client.new("http://community.asana.com/c/developers")
		@discourse_client.api_key = ENV['DISCOURSE_KEY']
		@discourse_client.api_username = "Jeff_Schneider"
		@all_dev_discourse_questions = get_all_dev_questions
		@all_dev_question_ids = get_all_dev_question_ids
		@store = YAML::Store.new('discourse-store.yml')
		@existing_database_ids = get_question_ids_from_store
		@new_question_ids = new_questions
		@question_ids_to_post_in_asana = []
		@asana_client = setup_asana_client
	end

	def get_all_dev_questions
		@discourse_client.category_latest_topics(category_slug: "developersAPI")
	end

	def get_all_dev_question_ids
		ids = []
		@all_dev_discourse_questions.each do |question|
			ids << question["id"]
		end
		ids
	end

	def get_question_ids_from_store
		ids = []
		@store.transaction do 
			ids = @store[:ids]
		end
		ids
	end

	# check if question has only 1 participant
	def only_one_participant?(question)
		question["details"]["participants"].count == 1
	end

	# check if question has been marked resolved
	# TODO: add logic
	def question_unresolved?(question)
		false
	end

	# subtract old questions from all questions
	def new_questions
		a = []
		@all_dev_question_ids.each {|id| a << id}
		b = []
		@existing_database_ids.each {|id| b << id}
		a-b
	end
	
	# iterate over new questions and check:
		# check if only 1 particiapnt and unresolved
	def check_if_unanswered
		@new_question_ids.each do |id|
			if only_one_participant?(@discourse_client.topic(id)) || question_unresolved?(@discourse_client.topic(id))
				@question_ids_to_post_in_asana << id
			end
		end
	end

	# post new questions to Asana
	#TODO build message in a different method
	def post_questions_to_Asana
		project_id = 123456
		tag = 123456
		@question_ids_to_post_in_asana.each do |id|
			title = @discourse_client.topic(id)["title"]
			discourse_user_id = @discourse_client.topic(id)["post_stream"]["posts"][0]["user_id"]
			asana_id = @discourse_client.user_sso(discourse_user_id)["external_id"]
			url = "Discourse URL: " + "https://community.asana.com/t/" + id.to_s
			message = "\n\n" + @discourse_client.topic(id)["post_stream"]["posts"][0]["cooked"] + "\n\n" + "User's Asana id: " + asana_id.to_s
			@asana_client.tasks.create(projects: [project_id], name: title, notes: url + message, tags: [tag])
		end
	end

	# update store to include all question ids to date
	def add_posted_ids_to_store
		@store.transaction do
			@store[:ids] += @question_ids_to_post_in_asana
		end
	end

	def print_results
		project_id = "123456"
		current_time = Time.new
		puts "As of : " + current_time.inspect
		if @question_ids_to_post_in_asana.count > 0
			puts "Found " + @question_ids_to_post_in_asana.count.to_s + " new community question(s):  https://app.asana.com/0/" + project_id
		else
			puts "No new community questions."
		end
	end

	def setup_asana_client
		Asana::Client.new do |c|
		  c.authentication :access_token, ENV['ASANA_PAT']
		end
	end

end

discourse_question_checker = DiscourseQuestions.new
discourse_question_checker.check_if_unanswered
discourse_question_checker.post_questions_to_Asana
discourse_question_checker.add_posted_ids_to_store
discourse_question_checker.print_results





