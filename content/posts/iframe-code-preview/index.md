---
layout: post
title:  "Building HTML, CSS, and JS code preview using iframe's srcdoc attribute"
date:   2022-04-27
tags:
  - web
  - css
  - javascript
  - html
  - hugo
  - blogging
categories:
  - frontend
cover: 
  image: cover.jpg
  alt: photo of code 
---

# A few words on code playgrounds

Many front-end developers and software companies blog about their trade. Oftentimes their writings include code examples with previews. 
Over the years a plethora of embeddable code playgrounds were created. 

Names such as CodePen, JSFiddle, JS Bin, or Plunker may ring a bell to you.

They're almost effortless to use, support frameworks, transpilers, preprocessors and other tooling that have evolved in the Javascript community over the years.

Using some of them might come with downsides or even serious consequences.

## Potential drawbacks of embedding third-party playgrounds

Embedding third-party playgrounds might be undesirable as some:

- 😱 make you add a `<script>` tag to embed the preview. The url points to provider's domain with no `integrity` attribute to check if the code hasn't been tampered with [^1].
- 🍪 welcome you with a huge cookie prompt,
- 🐢 are slow to load,
- 🕵️ track you and your visitors,
- 💸 companies behind them might go bankrupt and disappear along with your code previews.

There are of course bigger and lesser offenders.

It's a good idea to think twice before relying on any third-parties if your or your company's website is at stake. 

If you don't need all the fancy features this writeup will guide you through building a local code preview that works with your static site generator. It will be simple, inline, lightweight, durable and secure.

# Building a simple code preview

## What we will build

We will build a simple code preview with javascript support and code listings. The following example shows what we will achieve.

{{< code-preview >}}
{{< code-preview-file language="html" >}}
<p class="hello">This whole preview depicts what we will have at the end of the article.</p>
<p class="hello">This also supports javascript, not shown here.</p>
{{< /code-preview-file >}}
{{< code-preview-file language="css" >}}
.hello {
  background: none;
  border: 0;
  padding: 5px;
}
{{< /code-preview-file >}}
{{< /code-preview >}}

To make matters simple we will rely on features already present in static generators. 

The core concepts are transferable to any CMS, templating engine or even hand-crafted HTML, nothing stops you from building something similar for the technology you use.

The features that we will use include:
- templating (with sane escaping)
- code highlighting


## iframe's `srcdoc` attribute

You have likely heard of [iframes](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe), they allow you to embed third party websites into your website. 


What you might not be aware of is the iframe's `srcdoc` attribute, which allows to:

{{< blockquote link="https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe#attr-srcdoc">}}
Inline HTML to embed, overriding the src attribute. [...]
{{< /blockquote >}}

Perfect, that sounds pretty useful as we can just put our code in there without creating a separate page for every preview.

Let's start with something simple:

```html
<iframe srcdoc="<button>Hello world!</button>"></iframe>
```

{{< rawhtml >}}
<iframe srcdoc="<button>Hello world!</button>"></iframe>
{{< /rawhtml >}}

Quotes (`"`) need to be escaped using `&quot;`, as they would otherwise close the `srcdoc` attribute:

```html
<iframe srcdoc="<strong style=&quot;color: red;&quot;>Hello world!</strong>"></iframe>
```

{{< rawhtml >}}
<iframe srcdoc="<strong style=&quot;color: red;&quot;>Hello world!</strong>"></iframe>
{{< /rawhtml >}}

## Making it secure

By default this implementation isn't secure. 
The javascript inside can access the document outside the iframe.
It would be dangerous if included 3rd party JavaScript inside it.

The following code example illustrates the security concern.

```html
<iframe srcdoc="[...]"></iframe>
```

{{< rawhtml >}}
<div id="insecure-outside">This is an element outside of the iframe</div>
<iframe srcdoc="
<div id=&quot;secure-inside&quot; style=&quot;color: white;&quot;>This element is inside the iframe</div>
<button>modify something outside</button>
<script type=&quot;text/javascript&quot;>
document.querySelector(&quot;button&quot;).addEventListener(&quot;click&quot;, () => {
  document.getElementById(&quot;secure-inside&quot;).innerText = &quot;changed, ha!&quot;;
  parent.document.getElementById(&quot;insecure-outside&quot;).innerText = &quot;changed, ha!&quot;;
});
</script>
"></iframe>
{{< /rawhtml >}}

Fortunately, modern browsers provide means to sandbox the content inside `iframe`s.

### Introducing the `sandbox` attribute

You can isolate the content inside the `iframe` by using the [`sandbox`](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe#attr-sandbox) attribute.

The attribute:
{{< blockquote link="https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe#attr-sandbox">}}
Applies extra restrictions to the content in the frame. The value of the attribute can either be empty to apply all restrictions, or space-separated tokens to lift particular restrictions: [...]
{{< /blockquote >}}

[The list](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe#attr-sandbox) of restrictions is quite exhaustive and covers many aspects of modern web browsing.
An empty `sandbox` attribute will be too limiting, but let's start with `allow-scripts` and the same code as before.

```html
<iframe sandbox="allow-scripts" srcdoc="[...]"></iframe>
```

{{< rawhtml >}}
<div id="insecure-outside">This is an element outside of the iframe</div>
<iframe sandbox="allow-scripts" srcdoc="
<div id=&quot;secure-inside&quot; style=&quot;color: white;&quot;>This element is inside the iframe</div>
<button>modify something outside</button>
<script type=&quot;text/javascript&quot;>
document.querySelector(&quot;button&quot;).addEventListener(&quot;click&quot;, () => {
  document.getElementById(&quot;secure-inside&quot;).innerText = &quot;changed, ha!&quot;;
  parent.document.getElementById(&quot;insecure-outside&quot;).innerText = &quot;changed, ha!&quot;;
});
</script>
"></iframe>
{{< /rawhtml >}}

If you at the thjavascript console, you will notice that the code produces:

```
Uncaught DOMException: Permission denied to access property "document" on cross-origin object
```

This is what we wanted. Depending on you needs you could enable specific features on per preview basis.

## Adding code listings

Okay, so we a working secure prototype, but what's a code preview without a code listing?
Let's add a simple one. We will use the [`<pre>`](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/pre) element.

```html
<iframe sandbox="allow-scripts" srcdoc="<strong style=&quot;color: red;&quot;>Hello world!</strong>"></iframe>
<details>
<summary>Code</summary>
<pre>
&lt;strong style=&quot;color: red;&quot;&gt;Hello world!&lt;/strong&gt;
</pre>
</details>
```

{{< rawhtml >}}
<iframe sandbox="allow-scripts" srcdoc="<strong style=&quot;color: red;&quot;>Hello world!</strong>"></iframe>
<details>
<summary>Code</summary>
<pre>
&lt;strong style=&quot;color: red;&quot;&gt;Hello world!&lt;/strong&gt;
</pre>
</details>
{{< /rawhtml >}}


The preview looks okay for now, but we start to see some drawbacks.

The main one is that you need to duplicate the code. 
The escaping is also unwieldy. 

This proves the feasibility to build code previews using iframes. 
You can stop here and experiment with the idea yourself, 
or you might continue reading to get a full solution with language-based highlighting, and nice styles.

# Productionising the prototype

**Warning:** the rest of the article makes a heavy use of [Hugo](https://gohugo.io)'s features. 
They're transferable to other technologies, but expect to spend some time converting the ideas shown here. 


## Getting rid of code duplication with templates

If you are using a static site generator such as [Hugo](https://gohugo.io) or [Jekyll](https://jekyllrb.com) 
you will be familiar with templates.

We will focus on Hugo and native Go's templating features, but this can be easily translated to other templating languages.

Hugo supports [shortcode templates](https://gohugo.io/templates/shortcode-templates/).
With shortcodes we can expect to define something similar to:

```html
{{</* code-preview */>}}
  <p style="color:white;">We will build a simple code preview based on iframes</p>
{{</* /code-preview */>}}
```

and get the iframe with code listings without doing any escaping or code duplication.

First, create a file under `layouts/shortcodes/code-preview.html` and populate it with the following code. 

```html
<iframe sandbox="allow-scripts" srcdoc="{{ .Inner | safeHTMLAttr }}">
</iframe>
<details>
<summary>Code</summary>
<pre>
{{ .Inner | htmlUnescape }}
</pre>
</details>
```

Then, let's try to invoke it with the code listed above.

```html
{{</* code-preview */>}}
  <p style="color:white;">We will build a simple code preview based on iframes</p>
{{</* /code-preview */>}}
```

{{< iframe-code-preview/1 >}}
<p style="color:white;">We will build a simple code preview based on iframes</p>
{{< /iframe-code-preview/1 >}}

Looks promising, it doesn't look too elegant at the moment, but we will address it shortly.

## Making it pretty

It's time to style the preview. 
I don't plan to go into much detail as this isn't the main topic of this post.

The goal is to make the iframe look like a browser window and make code listings match the style of the iframe.

Let's: wrap the `iframe` with a `figure`, and add code highlighting. 

We will also fix a bug where first line was always blank using Hugo's [trim](https://gohugo.io/functions/trim/) function.

The `layouts/shortcodes/code-preview.html` should now look like:

```html
<figure class="code-preview">
    <iframe sandbox="allow-scripts" srcdoc="{{ .Inner | safeHTMLAttr }}">
    </iframe>
</figure>
<div class="code-preview--source">
<details class="code-preview--file">
    <summary>Code</summary>
    <div class="code-preview--file-content">
      {{- highlight (trim .Inner "\n") "html" }}
    </div>
</details>
</div>
```

Let's add some styles.
You can replace `var()` directives with colors of your choice.

```css
.code-preview {
	width: 100%;
	margin: 0 auto;
	display: flex;
	flex-direction: column;
  
	background: var(--tertiary);
	border: 6px solid var(--tertiary);
	border-radius: 5px;
}

.code-preview iframe {
	min-height: 300px;
	width: 100%;
	margin: 0 auto;
  
	border: 0;
	background: var(--code-bg);
}

.code-preview::before {
	width: 80%;
	height: 50%;
	margin: 5px auto;
	box-sizing: border-box;
  
	color: var(--secondary);
	background: var(--code-bg);
	border-radius: 5px;
	border-width: 6px 20px;
	text-align: center;
	font-size: 8pt;
	padding: 5px;
}

.code-preview--source {
	background-color: var(--code-bg);
	color: var(--secondary);
	display: flex;
	margin: 10px 0;
	border-radius: 5px;
	flex-wrap: wrap;
}

details.code-preview--file > summary {
	padding: 5px 10px;
	cursor: pointer;
	text-transform: uppercase;
	font-size: 10pt;
	min-width: 100px;
}

.code-preview--file {
	width: 100%;
	max-width: 100%;
}
```

Let's invoke the preview:

```html
{{</* code-preview */>}}
  <p style="color:white;">We will build a simple code preview based on iframes</p>
{{</* /code-preview */>}}
```

{{< iframe-code-preview/2 >}}
<p style="color:white;">We will build a simple code preview based on iframes</p>
{{< /iframe-code-preview/2 >}}

Not too shabby!


## Adding additional features

### Multiple code listings

Highlighting everything as `html` isn't ideal.
We would like to highlight `css`, `javascript`, and `html` respectively.
To achieve that we need to split the code into fragments based on their language.

We will use Hugo's nested templates to wrap our code snippets with additional metadata such as `language`. 

The invocation will now look like:
```html
{{</* code-preview */>}}
  {{</* code-preview-file language="html" */>}}
    <p class="class">We will build a simple code preview based on iframes</p>
  {{</* /code-preview-file */>}}
  
  {{</* code-preview-file language="css" */>}}
    .class {
      color: white;
    }
  {{</* /code-preview-file */>}}
{{</* /code-preview */>}}
```

Notice the `language` attribute inside the `code-preview-file`, this will hint the Hugo engine how to highlight the embedded snippet.

Let's define the `code-preview-file` shortcode under `shortcodes/code-preview-file.html`:

```html
{{- $language := .Get "language" }}
{{- if (eq $language "css" ) }}
<style type="text/css">
    {{- .Inner | safeCSS }}
</style>
{{- else if (eq $language "html" ) }}
    {{- .Inner | safeHTML }}
{{- else if (eq $language "javascript" ) }}
<script type="text/javascript">
    {{- .Inner | safeJS }}
</script>
{{- else }}
    {{- .Inner | safe }}
{{- end }}
{{-
    .Parent.Scratch.SetInMap "snippets" ( string .Ordinal )
    (dict "source" (trim .Inner "\n") "language" (.Get "language")) 
}}
```

There are a few things going on here. 

Firstly, based on the `language` parameter we include the appropriate boilerplate to embed the fragment into the document. The boilerplate can be either a `<style>` or `<script>`. 

Secondly, we use [Hugo's `.Scratch`](https://gohugo.io/functions/scratch/) to pass the snippet and the language used to the parent (`code-preview`) shortcode for the purpose of rendering code listings later.

The information that's passed will be a map resembling the following structure:

```text
snippets
 ├─0 (index)
 │  ├─language: html
 │  └─source: <p>[...]</p>
 └─1
    ├─language: css
    └─source: .class {[...]}
```

The parent (`shortcodes/code-preview.html`) will be able to access this object and create code listings.

We now need to adjust the parent template to pick the correct language hint when highlighting the code:

{{< highlight html >}}
<figure class="code-preview">
    <iframe sandbox="allow-scripts" srcdoc="{{ .Inner | safeHTMLAttr }}">
    </iframe>
</figure>
<div class="code-preview--source">
{{- range $key, $value := .Scratch.Get "snippets" }}
<details class="code-preview--file">
<summary markdown="span">{{ $value.language }}</summary>
<div class="code-preview--file-content">
{{- highlight $value.source $value.language }}
</div>
</details>
{{- end }}
</div>
{{< /highlight >}}

We iterate over the map we've built using the nested shortcode templates and display multiple code listings with appropriate highlighting.

Let's invoke the shortcode:

```html
{{</* code-preview */>}}
{{</* code-preview-file language="html" */>}}
  <p class="class">We will build a simple code preview based on iframes</p>
{{</* /code-preview-file */>}}
{{</* code-preview-file language="css" */>}}
.class {
  color: white;
}
{{</* /code-preview-file */>}}
{{</* /code-preview */>}}
```

{{< iframe-code-preview/3 >}}
{{< iframe-code-preview/file-3 language="html" >}}
<p class="class">We will build a simple code preview based on iframes</p>
{{< /iframe-code-preview/file-3 >}}
{{< iframe-code-preview/file-3 language="css" >}}
.class {
  color: white;
}
{{< /iframe-code-preview/file-3 >}}
{{< /iframe-code-preview/3 >}}

Fancy!

### Applying default styles to the content

While elements such as `<head>`, `<body>` aren't necessary in HTML5, 
it's sometimes desirable to have them inside the `iframe`. 

We can already achieve that by including the boilerplate in the `code-preview-file` fragments of language `html`
but that would obscure the listings.

We will modify the code preview to apply the boilerplate to every instance and also add some reset styles on top of that.

Let's modify the `shortcodes/code-preview.html` again:

```
<figure class="code-preview">
    <iframe sandbox="allow-scripts" srcdoc="{{ partial "code-preview.html" (dict "inner" .Inner) | safeHTMLAttr }}">
    </iframe>
</figure>
<div class="code-preview--source">
{{- range $key, $value := .Scratch.Get "snippets" }}
<details class="code-preview--file">
<summary markdown="span">{{ $value.language }}</summary>
<div class="code-preview--file-content">
{{ highlight $value.source $value.language }}
</div>
</details>
{{- end }}
</div>

{{ define "partials/code-preview.html" }}
<!doctype html>
<html lang="en">
<style>
    html, body {
        height: 100%;
        width: 100%;
        font-family: sans-serif; 
        color: rgb(218, 218, 219);
    }

    *, *::after, *::before {
        box-sizing: border-box;
    }
</style>
<body>
{{ .inner }}
</body>
</html>
{{ end }}
```

As including the whole boilerplate inside the `srcdoc` attribute wouldn't be handy, we define an inline [partial template](https://gohugo.io/templates/partials/) and reference it in the `srcdoc` attribute.

The partial template contains the regular `doctype`, `html` and `head` with some additional styles attached. You can customize it to your liking.


Here's the last invocation:

{{< iframe-code-preview/4 >}}
{{< iframe-code-preview/file-3 language="html" >}}
<p class="class">We will build a simple code preview based on iframes</p>
{{< /iframe-code-preview/file-3 >}}
{{< iframe-code-preview/file-3 language="css" >}}
.class {
  color: white;
  padding: 1em;
}
{{< /iframe-code-preview/file-3 >}}
{{< /iframe-code-preview/4 >}}

## The complete solution for Hugo

If you don't want to follow the whole process of building the code preview yourself here are all the files needed to achieve it.

### shortcodes/code-preview.html
```html
<figure class="code-preview">
    <iframe sandbox="allow-scripts" srcdoc="{{ partial "iframe-code-preview.html" (dict "inner" .Inner) | safeHTMLAttr }}">
    </iframe>
</figure>
<div class="code-preview--source">
{{- range $key, $value := .Scratch.Get "snippets" }}
<details class="code-preview--file">
<summary markdown="span">{{ $value.language }}</summary>
<div class="code-preview--file-content">
{{ highlight $value.source $value.language }}
</div>
</details>
{{- end }}
</div>

{{ define "partials/iframe-code-preview.html" }}
<!doctype html>
<html lang="en">
<style>
    html, body {
        height: 100%;
        width: 100%;
        font-family: sans-serif; 
        color: rgb(218, 218, 219);
    }

    *, *::after, *::before {
        margin: 0;
        box-sizing: border-box;
    }
</style>
<body>
{{ .inner }}
</body>
</html>
{{ end }}
```

### shortcodes/code-preview-file.html

```html
{{- $language := .Get "language" }}
{{- if (eq $language "css" ) }}
<style type="text/css">
    {{- .Inner | safeCSS }}
</style>
{{- else if (eq $language "html" ) }}
    {{- .Inner | safeHTML }}
{{- else if (eq $language "javascript" ) }}
<script type="text/javascript">
    {{- .Inner | safeJS }}
</script>
{{- else }}
    {{- .Inner | safe }}
{{- end }}
{{-
    .Parent.Scratch.SetInMap "snippets" ( string .Ordinal )
    (dict "source" (trim .Inner "\n") "language" (.Get "language")) 
}}
```

### The stylesheet

```css
.code-preview {
	width: 100%;
	margin: 0 auto;
	border: 6px solid rgb(65, 66, 68);
	border-radius: 5px;
	display: flex;
	overflow: auto;
	flex-direction: column;
	background: var(--tertiary);
	background: rgb(65, 66, 68);
}

.code-preview iframe {
	min-height: 300px;
	width: 100%;
	margin: 0 auto;
	border: 0;
	background: #272822;
}

.code-preview::before {
	color: var(--secondary);
	background: #272822;
	width: 80%;
	height: 50%;
	margin: 5px auto;
	border-radius: 5px;
	border-width: 6px 20px;
	box-sizing: border-box;
	text-align: center;
	font-size: 8pt;
	padding: 5px;
}

.code-preview--source {
	background: rgb(65, 66, 68);
	color: rgb(218, 218, 219); 
	display: flex;
	margin: 10px 0;
	border-radius: 5px;
	flex-wrap: wrap;
}

details.code-preview--file > summary {
	padding: 5px 10px;
	cursor: pointer;
	text-transform: uppercase;
	font-size: 10pt;
	min-width: 100px;
}

.code-preview--file {
	width: 100%;
	max-width: 100%;
}
```

### An exemplary invocation

```html
{{</* code-preview */>}}
{{</* code-preview-file language="html" */>}}
<p id="css">We will build a simple code preview based on iframes</p>
{{</* /code-preview-file */>}}

{{</* code-preview-file language="css" */>}}
#css {
  text-decoration: underline;
}
{{</* /code-preview-file */>}}
{{</* /code-preview */>}}
```

[^1]: If the playground is compromised your website will likely be compromised as well.