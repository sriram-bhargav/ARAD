# ARAD
Ads Platform for Augmented Reality Apps! 

# Why did we build ARAD?

Developers work hard. They deseve money. Advertising is a well known way to monetize on apps. The idea is to bring in-app advertising into AR apps via a simple SDK/API.

# How?

- We used open sourced AR Game, [TicTacToe](https://github.com/bjarnel/arkit-tictactoe) to build a sample SDK on top to show how to easily add an AR Ad to any AR app. We used Apple's [ARKit](https://developer.apple.com/arkit/) to help place context relevant ads in the surrounding environment without intruding the game flow. There are two parts to the ARAD platform:

  - Recognizing and serving context specific ads in a non-intrusive way to the user so it does not distract from the game flow
  - Providing a way for the developer and advertiser to track metrics around the ads (like impressions, conversions) 

Apple’s ARKit does a decent job detecting objects our surroundings. We used an open sourced ML library, [InceptionV3](https://github.com/tensorflow/models/tree/master/inception) on top of this to help classify the objects present in an image. We then send this information to our backend, AdServer that let us decide which advertisement best fit the scene. This [AdServer](http://yesteapea.com/arad/new) serves two purposes: 

  - Lets an advertiser onboard an advertisement easily, by uploading media assets (for example images, videos, 3D models etc) and suggested keywords for displaying the advertisement. In future, we intend to extend this to include CPM, Bidding etc. 
  - We also built a simple [dashboard](http://yesteapea.com/arad/dashboard/408051505655861.9) in the AdServer that gave the advertiser insights into how the ad was doing with the given keywords. The dashboard displays conversions and impressions, [here](http://yesteapea.com/arad/list) you can find an example of all the advertisements that we placed in the real world.

If this is done in a real company setting, we would be exporting an SDK and API that developers can use to easily augment the reality with ads.

# Requirements for Demo
Objects that we have ads for: iphone, a laptop, a coke or water bottle

# Demo
- We made a simple demo AR game like TicTacToe. Here is an example of how in-app advertising looks like [currently](https://thenextweb.com/wp-content/blogs.dir/1/files/2014/02/Angry-Birds-on-Android-Hits-3M-Downloads-Free-with-Google-s-AdMob-2.jpg).
- Now an advertisement adds an AR advertisement into our [ADServer](http://yesteapea.com/arad/new) with relevant keywords for which the ad should show up. The advertiser also uploads a media asset so we can place this in real world and augment objects matching the keywords.
- When a user plays the game and browses around while taking a break, lets say he runs into a coke bottle in his environment. The AdServer shows the advertisement in a non-intrusive way, when the user clicks the banner the advertisement expands to display the media content attached to the advertisement. 
- From the advertiser's perspective, when they visit the Ads dashboard and refresh the page they can view the impressions and clicks.

# Team

- Jaydev Ajit Kumar
- Sriram Bhargav
- Sai Teja Pratap
- Spandana Govindgari

# Resources
https://github.com/tensorflow/models/tree/master/inception

