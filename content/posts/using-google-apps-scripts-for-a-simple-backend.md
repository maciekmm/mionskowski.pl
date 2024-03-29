---
layout: post
title:  "Using Google Apps Scripts for a simple backend"
date:   2016-03-20
tags:
 - google
 - go
categories:
- backend
comments: true
aliases:
 - /using-google-apps-scripts-for-a-simple-backend
---

I'm not that much of a frontend guy, but I was encouraged by the technology pace used in browsers to play with it. My goal was simple - create a website that imitates a native app. I didn't have any brilliant ideas at the time therefore my choice fell on a simple student app for my school featuring:

- Timetable (group filtered) (the [original plan](http://www.vlo.gda.pl/vlo/sites/default/files/uploads/PLAN%202015-16.xls) is in excel format)
- Lucky number - every student in a group has it's number assigned based on alphabetical order of his name and every day a number is drawn resulting in some protection from lack of homework and small unannounced exams
- News scraped from [school's website rss](http://www.vlo.gda.pl/vlo/?q=rss.xml)
- Teachers quotes - students have made a facebook page which stores funny teacher statements

I needed a **backend** for it, and it's what this article is all about.

## Making choices

I didn't want to use technology I know well. The biggest wrinkle was parsing the timetable. I was googling about parsing *xls* files and stumbled upon google sheets. My question was how am I going to extract parsed data, the answer was simple: **[Apps Script Execution API][1]**. It's free and lets you execute any script you create. That meant I could use forms to enter lucky-number (it's drawn by hand every morning so I can't do much about it) so I didn't have to waste time on creating UI, authentication and implementing xls parsers.

## Disclaimer

> **Google Apps Scripts** are not guaranteed to have a constant uptime and low latency. Therefore it's not recommended to use it in production environment for *serious* projects.

## Writing scripts

First and foremost you need to create a Google Apps Script project. You can do this by going to your google drive, connecting **Google Apps Script** in `New -> More -> Connect more apps` tab and creating an apps script afterwards like any other document.

The spreadsheet reference can be found [here](https://developers.google.com/apps-script/reference/spreadsheet/)

All scripts I've created for the student app are located on project's [github](https://github.com/VLO-GDA/gapp-scripts) repository.

I've picked a lucky number one, as it's fairly straight-forward and has a dirty workaround for form authentication: I simply made an additional validation field (Do not name it `password` though, that will result in banning your form automatically).

~~~js
//Google forms can't be protected, so we decided to add additional password field
var password = "";
var luckyNumber = SpreadsheetApp.openById("10RW_TNyLvqrueEiBxcmob4SbJEsJU9S5UWpG6Tj6a1I").getSheets()[0];

/**
 * Gets latest lucky number
 **/
function getLuckyNumber() {
  //timestamp,number,password
  for (var i = luckyNumber.getLastRow(); i > 0; i--) {
    var range = luckyNumber.getRange(i, 1, 1, 3).getValues();
    if (range[0][2] != password) {
      continue;
    }
    return JSON.stringify({
      date: new Date(range[0][0]).getTime(),
      number: parseInt(range[0][1])
    });
  }
}
~~~

As you can see the script is pretty straight-forward:

- It gets the form answer sheet
- Loops through answers from the end and picks the latest one with correct password there is
- Takes the timestamp and value of the form submitted and encodes it to JSON string

The JSON string is being returned [Apps Script Execution API][1] basically forwards it to the execution request. 

I won't cover configuring a project in [developers console](https://console.developers.google.com/home/dashboard?project=project-id-fniionhgmbisgzhqrpo), but you need to enable *Google Apps Script Execution API* and set up *Credentials* for *Other*.

## Proxifying requests

Executing any function in our script requires us to be authenticated. To do that we will some kind of a authentication proxy.

I went with `go` and created pretty [simple app](https://github.com/VLO-GDA/server-app) based on the example found in [execution api docs](https://developers.google.com/apps-script/guides/rest/quickstart/go).

I've created a simple wrapper to easily add new endpoints with input validation and so forth.

~~~go
tt := &Proxy{
	Service: srv,
	Script:  scriptID,
	Name:    "getTimetable",
	Params: map[string]Middleware{
		"group": func(group string) (interface{}, error) {
			//Group validation
			return group, nil
		},
	},
}
// "group" is the included parameter
router.GET("/timetable/group/:group", tt.Handle)
~~~

It works pretty well, you can check it out here: [vapi.maciekmm.net/timetable/group/IIID](https://vapi.maciekmm.net/timetable/group/IIID)

The [Proxy](https://github.com/VLO-GDA/server-app/blob/master/proxy.go) code due to Google generating their [API](google.golang.org/api/script/v1) is terrible in terms of design.


## Conclusion

It was a fun project. Using [Google Apps Scripts](https://developers.google.com/apps-script/) and [Execution API][1] while fun cannot be applied in professional environment as latency which varies from 500ms to over 1s and uptime aren't great.

There was little code, I managed to develop the whole app in 10-15 hours which given the fact I've never used [vue.js](https://vuejs.org/) nor Google Apps Scripts is from my perspective a good result.

Using Google Sheets also made it stupid easy to make graphs from for instance lucky-number appearence frequency which ... is cool, isn't it?

![Lucky Number appearance frequency](/downloads/ln-frequency.png)

*I have a feeling the person drawing the number has 19 <sup>/s</sup>*

The finished product can be found here: [vlo.maciekmm.net](https://vlo.maciekmm.net/), your eyes may hurt from viewing this on desktop thus I encourage you to view it either on your mobile phone or shrink the viewport in developer console of some sort.

[1]: https://developers.google.com/apps-script/guides/rest/