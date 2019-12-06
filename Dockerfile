FROM elixir:latest

RUN apt-get update -y
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash -
RUN apt-get install -y nodejs
RUN apt-get install -y inotify-tools

RUN mkdir /app
COPY . /app
WORKDIR /app

RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get
RUN cd assets && npm i && cd ..
RUN mix do compile

EXPOSE 4000
CMD mix phx.server



