./node_modules/coffee-script/bin/coffee -o dist/js/ -c src/script/
./node_modules/stylus/bin/stylus src/styles/vhh-video-player.styl -o dist/css/vhh-video-player.css
./node_modules/stylus/bin/stylus src/styles/vhh-filmstrip.styl -o dist/css/vhh-filmstrip.css
cp ./node_modules/hls.js/dist/hls.js ./dist/js/vendor/hls.js
cp ./node_modules/jquery/dist/jquery.js ./dist/js/vendor/jquery.js
cp -R ./node_modules/font-awesome/fonts/ ./dist/css/fonts/
cp ./node_modules/font-awesome/css/font-awesome.css ./dist/css/vendor/font-awesome.css