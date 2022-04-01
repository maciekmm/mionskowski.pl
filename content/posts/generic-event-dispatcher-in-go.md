---
layout: post
title:  "Generic event emitter/dispatcher in Go"
date:   2015-12-26
tags:
 - go
 - reflection
 - event driven
categories:
 - backend
comments: true
aliaes:
 - /generic-event-dispatcher-in-go
---

Go doesn't support generics, one can use `go generate`, but writing code for that is a pain. Instead we can tinker with reflection to manipulate types and channels. This allows us to create neat event **dispatcher** with user friendly handler registration and somewhat reasonable event registration.

Event emitters are pretty popular in OOP languages which support generics, but of course Go is not one of them. We will try to achieve something similar without generic types.

## Goals

We want to have a solution that is as user friendly as possible and thread-safe. Let's bring some code fragments to show how easy it can be.

### Listener Registration

~~~go
channel := make(chan SomethingHappened, 5)
ok := dispatcher.RegisterListener(channel) //This registers a listener for event - SomethingHappened
for {
	select {
	case event := <-channel:
	//Do something with it (already SomethingHappened type)	
	}
}
~~~

### Event Registration

Well, we can omit this part and have registering a listener register an event as well, but doing it this way is more verbose and adds possibility for returning bool value or error if the operation fails. It also makes it possible to unregister the event.

~~~go
ok := dispatcher.RegisterEvent((*SomethingHappened)(nil)) //Magical nil pointer
~~~

## Development

[Reflection](https://golang.org/pkg/reflect/) in Go is pretty powerful, well documented and maybe not as fast as some would like it to be, but it's reasonable. We can sacrifice some performance in favor of user-friendlyness and code universality. It's usually better to have exact requested type returned than mess with type assertion.

We need some way of storing event -> listeners relations, map is the perfect fit for that. *Un*fortunately, it is not thread-safe, therefore we need some mutex, I'll go with [RWMutex](https://golang.org/pkg/sync/#RWMutex) to not hit performance much. We also don't want anyone to tinker with it, so we don't export fields and it's why doing a factory is mandatory.

~~~go
type Event interface {
	//Some methods here
}

type Dispatcher struct {
	handlers map[reflect.Type][]reflect.Value
	lock     *sync.RWMutex
}

func NewDispatcher() *Dispatcher {
	return &Dispatcher{
		handlers: make(map[reflect.Type][]reflect.Value),
		lock:     &sync.RWMutex{},
	}
}
~~~
`map[reflect.Type][]reflect.Value` is probably something that caught your attention. During runtime It's a channel accepting specific event and I've decided to store `reflect.Value` instead of an `interface{}` because it has direct [function(s)](https://golang.org/pkg/reflect/#Value.TrySend) to send data through channels. Now that we have the basic architecture covered, let's move to more *magic* stuff.

### Event Registration

~~~go
func (d *Dispatcher) RegisterEvent(event Event) bool {
	d.lock.Lock()
	defer d.lock.Unlock()
	typ := reflect.TypeOf(event).Elem()
	if _, ok := d.handlers[typ]; ok {
		return false
	}
	var chanArr []reflect.Value
	d.handlers[typ] = chanArr
	return true
}
~~~
Let's start with function parameter. As you can see we accept an interface. Intuition may suggest that `reflect.Type` should be accepted, but that would result in very ugly event registration: `reflect.TypeOf((*SomethingHappened)(nil)).Elem()`. This is definitely something we need to avoid. Where the *magic* mentioned happens is `typ := reflect.TypeOf(event).Elem()`. Let's quickly walk through that:

~~~cucumber
Given the input is (*SomethingHappened)(nil):
	When reflect.TypeOf(input) is called
	Then *SomethingHappened is returned
	
Given the input is *SomethingHappened:
	When Elem() is called
	Then SomethingHappened is returned
~~~

Some perceptive people could spot a reference to [cucumber](https://cucumber.io/) - Even though I don't use it (you can probably spot like 10 errors in above *walk-through*) I love the idea :)

If you didn't understand the aforementioned scenerio, `TypeOf()` returns the most *top-level* type channel/interface/pointer or type. `Elem()` essentially dereferences it, thus extracts what is passed in channel, what type is under pointer etc.

### Listener Registration

~~~go
// RegisterListener registers channel accepting desired event - a listener.
// It is important to note that what channel accepts determines what will be sent to it.
// If listened event is not registered false is returned
// It's advised to use a buffered channel for the listener, otherwise events might be lost in action.
// Panics if pipe is not a channel
func (d *Dispatcher) RegisterListener(pipe interface{}) bool {
	d.lock.Lock()
	defer d.lock.Unlock()
	channelValue := reflect.ValueOf(pipe)
	channelType := channelValue.Type()
	if channelType.Kind() != reflect.Chan {
		panic("Trying to register a non-channel listener")
	}
	channelIn := channelType.Elem()
	if arr, ok := d.handlers[channelIn]; ok {
		d.handlers[channelIn] = append(arr, channelValue)
		return true
	}
	return false
}
~~~

When registering a Listener we need to be more careful with what we operate on, storing non-channel value in map would cause dispatch loop to panic and that's definitely something we need to avoid. The code is really similar to one that registers an event. One interesting thing happens here though - I don't inline calls if something is called more than once. I have to admit I was lazy and didn't check if getting `reflect.Type` from `reflect.Value` comes with noticable performance cost, so I made additional variable to *cache* it, forgive me. Well, the main point is to show that you need to be very careful when working with [reflect](https://golang.org/pkg/reflect) package or reflection in general in any language.

### Dispatch Loop

~~~go
// Dispatch provides thread safe method to send event to all listeners
// Returns true if succeeded and false if event was not registered
func (d *Dispatcher) Dispatch(event Event) bool {
	d.lock.RLock()
	defer d.lock.RUnlock()

	eventType := reflect.TypeOf(event).Elem()
	if listeners, ok := d.handlers[eventType]; ok {
		for _, listener := range listeners {
			listener.TrySend(reflect.ValueOf(event).Elem())
		}
		return true
	}
	return false
}
~~~
This function is pretty straight-forward. We read lock our dispatcher, get event's type, look it up and send to every listener. It has one really major drawback though - the same copy is sent to every listener, therefore we either need to expose functions that clone props on the fly or clone the whole struct ourselves. This is the trickiest part, and there's no *right* answer for that.
For my needs I've added a `Clone()` method to Event interface. This requires every struct that inherits any `Clone()` function - from anonymous fields for instance to override that function. Let's call the clone method then:

`listener.TrySend(reflect.ValueOf(event.Clone()).Elem())`

## Tests

I've written a simple app to use the event handler. I made a buffered channel with two elements to see what happens if channel is overflowed and a struct with string pointer so we can test cloning.

- [playground](http://play.golang.org/p/gqk9PxK5I8)

Hit run and wait for an output.

As you can see two out of three messages were passed due to two element channel and synchronous receiving, cloning works and it dispatches successfully. 

## Summing up

As you can see [reflect](https://golang.org/pkg/reflect) package is a great tool and with great tools come great features. Doing a dispatcher with less reflection would be much more painful and problematic. With the foregoing solution we can set up our listeners with a few easy steps that are understandable even for a Go newbie. If you have any ideas on improving my solution feel free to tell me that in comments - critique is highly appreciated - it's how you learn new things, isn't it?

Finished dispatcher can be found [here](https://gist.github.com/maciekmm/4c291b6c8c0ac789efba);
