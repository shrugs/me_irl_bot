all: build run

build:
	docker build -t dokku/slackny-me_irl_bot .

run:
	docker run -it -e "SLACK_API_TOKEN=${SLACK_API_TOKEN}" dokku/slackny-me_irl_bot
