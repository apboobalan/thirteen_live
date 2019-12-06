#ubuntu/bionic64 Built inside server.
#Install elixir and nodejs.
#wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && sudo dpkg -i erlang-solutions_2.0_all.deb
#sudo apt-get -y update
#sudo apt-get -y install esl-erlang
#sudo apt-get -y install elixir
#curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
#sudo apt-get -y install nodejs

git clone https://github.com/apboobalan/thirteen_live.git
cd thirteen_live

mix local.hex --force
mix local.rebar --force
mix deps.get
cd assets && npm i && cd ..

REALLY_LONG_SECRET=$(mix phx.gen.secret)
export SECRET_KEY_BASE=$REALLY_LONG_SECRET

# Initial setup
mix deps.get --only prod
MIX_ENV=prod mix compile

# Compile assets
npm run deploy --prefix ./assets
mix phx.digest

MIX_ENV=prod PORT=80 mix release

cd ..
mv thirteen_live/my_releases release_$(date +%Y_%m_%d_%H_%M_%S)
rm -rf thirteen_live
