var path = require( 'path' );
const webpack = require('webpack');

module.exports = {
  entry: './index.js',

  output: {
    path: path.join( __dirname, 'dist' ),
    filename: 'index.js'
  },

  resolve: {
    extensions: ['.js', '.elm']
  },

  plugins: [
    new webpack.NoEmitOnErrorsPlugin()
  ],

  module: {
    rules: [
      {
        test: /\.html$/,
        exclude: /node_modules/,
        use: 'file-loader?name=[name].[ext]'
      },
      {
        test: /\.elm$/,
        exclude: [/elm-stuff/, /node_modules/],
        use: [
          {
            loader: 'elm-hot-loader'
          },
          {
            loader: 'elm-webpack-loader',
            options: {
              debug: false
            }
          }
        ]
      },
    ]
  },

  target: 'web',

  devServer: {
    inline: true,
    hot: true,
    stats: 'errors-only'
  }
};