FROM ruby:2.3.3-onbuild

WORKDIR /usr/src/app
ENTRYPOINT ["bundle", "exec"]
CMD ["rackup", "config.ru"]
