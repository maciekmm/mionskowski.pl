---
layout: post
title:  "Unmasking a Go HTML Parser Bug with Differential Fuzzing"
date: 2023-10-24
tags:
 - go
 - security
 - fuzzing
categories:
 - backend
cover:
  image: cover.png
  alt: Go gopher in deep thought, holding a shattered HTML tag, with a "Fuzzer" machine showing electrical bursts.
---

In this write-up, we'll delve into how, through differential fuzzing, we uncovered a bug in Go’s exp/net HTML’s tokenizer. We'll show potential XSS implications of this flaw. Additionally, we'll outline how Google assessed this finding within their VRP program and guide how to engage and employ fuzzing to evaluate your software.

# Introduction

Reminisce with me the discussion boards of 2005. Open to all, searchable from every corner, with no account needed to peek in. Ah, those golden days of thriving communities and quality content. Imagine we're building one now though, in Go.

{{< figure src="./forum.png" alt="a screenshot from a phpBB community forum" align=center title="phpBB is an open-source forum software" >}}

Pardon my sentiment for a moment. Let's dive into a feature you might find essential for the product: **support of safe HTML in user content, like `<strong>`.**. Yes, there's markdown, BBCode and other markup languages out there which one should use instead. Ignore those sane options for a minute though.

Early 2000s had a quite lax attitude towards security, but we're well into a third decade of the century now and leaving a site vulnerable to XSS attacks wouldn't end up well. And so we'll need to make sure that our validation code is effective at stopping bad actors.

# How'd you check if a HTML is safe?

Since we're building this in Go we might be aware of the `html` package, which according to the documentation:

{{< blockquote link="https://pkg.go.dev/golang.org/x/net/html" >}}
Package `html` implements an HTML5-compliant tokenizer and parser
{{< /blockquote >}}

Assuming the tokenizer operates equally to how it does in a browser, one might believe the following code to be secure. 

In short, we are filtering out anything that's not `strong` or has HTML attributes.

```go
func IsSafe(content io.Reader) bool {
	tok := html.NewTokenizer(content)
	for {
		tt := tok.Next()
		switch tt {
		case html.StartTagToken:
			name, hasAttr := tok.TagName()
			if hasAttr || string(name) != "strong" {
				return false
			}
		case html.ErrorToken:
			if tok.Err() == io.EOF {
				return true
			}
			return false
		case html.TextToken, html.EndTagToken:
		default:
			return false
		}
	}
	return true
}
```

Let's also write some tests to raise our confidence in the solution:

```go
func TestIsSafe(t *testing.T) {
	expected := map[string]bool{
		"<strong>test</strong>":                 true,
		"<script>test</script>":                 false,
		"<script/>test":                         false,
		"<b>test</b>":                           false,
		`<strong onclick="">test</strong>`:      false,
		`<!-- comment --><strong>test</strong>`: false,
	}

	for payload, safe := range expected {
		payload := payload
		safe := safe
		t.Run(payload, func(t *testing.T) {
			if IsSafe(strings.NewReader(payload)) != safe {
				t.Fatalf("expected %v for %s", safe, payload)
			}
		})
	}
}
```

```go
$ go test -run=TestIsSafe
PASS
ok      github.com/maciekmm/fuzz-net-http       0.002s
```

Despite all our tests passing, something doesn't sit right with me. Examining [the Tokenizer implementation](https://github.com/golang/net/blob/master/html/token.go), 
it's evident that it doesn't strictly follow the [WHATWG spec](https://html.spec.whatwg.org/multipage/parsing.html#tokenization) that shows an explicit state machine.

For instance, when reviewing the following snippet from the net/html source code[^1], it's clear there aren't defined state transitions. It seems to parse content in a pretty naive way.

[^1]: [readTag function in the html.Tokenizer source code](https://github.com/golang/net/blob/d23d9bc549229fd1a9d375dc91141fcf1385d257/html/token.go#L902-L929)

So with that information we'd like to understand if our `IsSafe` function is actually safe (spoiler alert - it's not) and under what circumstances it would trip. To do that we'll use [differential fuzzing](https://en.wikipedia.org/wiki/Differential_testing).

# What is fuzz testing and differential fuzzing

In short, fuzz testing is a type of testing that involves **generating random inputs and passing them to the system being tested**. In the standard fuzz testing approach, the fuzzing engine usually monitors the program for crashes and unexpected memory accesses. Most of the time when writing fuzzers no explicit assertions are made. [Fuzz testing is extremely effective](https://github.com/google/oss-fuzz#trophies) at finding vulnerabilities. However, what I find even more effective is differential fuzzing, where two implementations of a given logic are compared against each other.

Regular Fuzz tests complement your unit test suite really well. I'll argue they are easier to write than unit tests, since you usually don't make assertions. Furthermore, existing unit tests can be converted to fuzz tests with minimal effort.

I won't go into more detail how Fuzzing works, there are great resources online, take a look at the excellent [Go Fuzzing Tutorial](https://go.dev/security/fuzz/) for examples or have a look at the following two code snippets.

Your simplest fuzz test will look like this:

```go
func FuzzFoo(f *testing.F) {
    f.Add("bar") // seed corpus

    f.Fuzz(func(t *testing.T, in string) {
        Foo(in) // function being tested
    })
}
```

Your differential fuzz test will look like this:

```go
func FuzzFoo(f *testing.F) {
    f.Add("bar") 

    f.Fuzz(func(t *testing.T, in string) {
        if(YourFooImpl(in) != ReferenceFooImpl(in)) {
            t.Fail()
        }
    })
}
```

# Picking a fuzz testing candidate

Below is a non-exhaustive list of what I consider to be good fuzz testing candidates:

- parsers
- encoders/decoders
- marshallers/unmarshallers
- complex code in general that can be unit tested

The code should also:
- be snappy to execute - fuzz testing benefits from high throughput
- have no side effects - to not confuse the fuzzing engine 

# Fuzzing the Go standard library

A few months ago, a friend of mine found a security vulnerability in Go's HTML tokenizer, [recorded a video about it](https://www.youtube.com/watch?v=H1TVk3HhL9E), and was featured in the Go Weekly newsletter. 

Tokenizing is one of the first steps when parsing HTML. It's also a step required for input sanitization to accept HTML user generated content. 

Seeing how complex the tokenizer codebase is, I knew this was a good candidate for fuzzing and it was likely that there are more bugs lurking around the codebase so I decided to give it a go. I assumed it's already pretty well tested to not crash, so I'm mostly after logic issues and spec non-compliance. Since regular fuzzing won't detect business logic discrepancies, we'll need differential fuzzing for that.

## Looking for a second tokenizer implementation 

We'll need a second implementation to compare against. The initial idea was to use a tokenizer from a web browser engine such as Blink or Servo. The problem with those tokenizer is that they are not easy to extract from the complex codebase nor write C bindings for. Although we could use something like [SWIG](https://www.swig.org/Doc3.0/Go.html) I decided not to as I was just starting with fuzzing at that point and needed something easy to evaluate my approach. I thought there must be something out there written in C that I can call via CGO. And indeed there's - [Lexbor](https://github.com/lexbor/lexbor).

Lexbor claims to be more or the less what we need.
> We build a web browser engine available as a software library; it ships under the Apache 2.0 license and has no extra dependencies. 

Sounds about to be what we're after.

## What shall we compare?

To visualize the tokenization process consider the following input:
```html
<strong>test</strong><a>
```

Tokenization will split the input into tokens, in this case:
```
StartTag - strong
Text     - test
EndTag   - strong
StartTag - a
```

We could compare the tokenization output of two implementations and fail the test if it differs.

To start off let's write a simple abstraction to represent the list of tokens coming from both implementations:

```go
type Token struct {
	Name string
	Type html.TokenType
}

type TokenizeFunc func(input string) ([]Token, error)
```

I'll skip implementation details for now, as it's mostly translating the API of Lexbor and net/html to this new implementation. You'll find links to the code towards the end of this post.

## Building Our Fuzzing Test

Given the implementation above we can start comparing the outputs. In essence the fuzz test should look as follows:

```go
func FuzzTokenize(f *testing.F) {
	for _, test := range tests {
		f.Add(test)
	}

	f.Fuzz(func(t *testing.T, input string) {
		lexborTokens, err := LexborTokens(input)
		if err != nil {
			t.SkipNow()
		}

		netTokens, err := NetTokens(input)
		if err != nil {
			t.SkipNow()
		}

		if !reflect.DeepEqual(lexborTokens, netTokens) {
			t.Errorf("lexbor tokenization mismatches net/html tokenization: for: %s, lexbor: %v, net: %v", lexborTokens, netTokens, input)
			return
		}
	})
}

```

Note that the actual implementation is much more complex as it has to handle discrepancies between the tokenizers, and there are a ton!

I won't go into more implementation details in this blog post. You can find the implementation [in this repository](https://github.com/maciekmm/go-std-lib-fuzz/). It's a bunch of hacky CGO code on top of more hacky comparison code. We won't catch all the bugs, but it's a good start.

## Fuzz Test Outcomes

So let's see what happens when we run the fuzz test now.

```go
go test -fuzz=FuzzTokenize -run=^$
fuzz: elapsed: 0s, gathering baseline coverage: 0/11 completed
fuzz: elapsed: 0s, gathering baseline coverage: 11/11 completed, now fuzzing with 20 workers
fuzz: elapsed: 1s, execs: 201040 (297903/sec), new interesting: 139 (total: 150)
--- FAIL: FuzzTokenize (0.68s)
    --- FAIL: FuzzTokenize (0.00s)
        lexbor_test.go:65: length mismatch: 
            lexbor      =[{Name:a Type:StartTag}], 
            net =[]
             not equal, input: <A =">
```

What this means is that `net/html` Tokenizer does not see any HTML tags in that input, whereas Lexbor sees an `a` tag. 

Let's take `<A =">` and make it execute some JS like `<script =">alert(1)</script>`.

{{< figure src="./alert1.png" alt="an alert dialog printing 1" align=center title="woops!" >}}

Let's see what our `IsSafe` function thinks about it by expanding our test suite:


```diff
@@ -13,6 +13,7 @@ func TestIsSafe(t *testing.T) {
                "<script/>test":                    false,
                "<b>test</b>":                      false,
                `<strong onclick="">test</strong>`: false,
+               `<script =">alert(1)</script>`:     false,
        }
```

```go
--- FAIL: TestIsSafe (0.00s)
    --- PASS: TestIsSafe/<strong>test</strong> (0.00s)
    --- PASS: TestIsSafe/<script>test</script> (0.00s)
    --- PASS: TestIsSafe/<script/>test (0.00s)
    --- PASS: TestIsSafe/<b>test</b> (0.00s)
    --- PASS: TestIsSafe/<strong_onclick="">test</strong> (0.00s)
    --- FAIL: TestIsSafe/<script_=">alert(1)</script> (0.00s)
FAIL
exit status 1
```

The issue stems from the incorrect parsing of attributes in the tag. The spec allows _dangling_ `=` characters, but the Tokenizer doesn't support it.

Let's take it to the Google Vulnerability Program (VRP)

# Google Vulnerability Program

## Reporting the finding to VRP


We've found a bug in the Tokenizer which may or may not be viewed as a security concern.
As a result, I've decided to submit it to the Google Vulnerability Program, maybe I could get some coffee pocket change.

{{< blockquote >}}
**Details**

There's parsing inconsistency between `x/net/html.Tokenizer` and web browsers leading to potential XSS injection attack.

Consider the following input: `<script>alert(window.location.href)</script>`. When ran through html.Tokenizer one will get html.StartTagToken with a Token.Data equal to script followed by EOF ErrorToken This is a correct and expected behavior.

Consider a very similar input: `<script =">alert(window.location.href)</script>`. This time around the html.Tokenizer only shows the EOF ErrorToken, while browser parses this to `<script ="="">alert(window.location.href)</script>` potentially leading to script injection and execution.

"x/net/html" version: v0.7.0
Attack scenario

Consider a website with a comment system where certain HTML tags are allowed. For the purpose of this report let's say h1 are safe and allowed. To make sure that comments only have h1 tags one will use the x/net/html.Tokenizerand listen for `html.StartTagToken` or `html.SelfClosingTagTokens`.

Due to this vulnerability an attacker can smuggle a `<script>` tag and execute arbitrary javascript on the website leading to XSS and potential data exfiltration from the website.
{{< /blockquote >}}

After about two weeks Google responded with the following:

{{< blockquote >}}
**Status: Won't Fix (Intended Behavior)**

This is working as intended. Tokenizer just tokenizes, it doesn't guarantee that the input will be *parsed* the same by the browser. When the HTML semantics matter (and they do for XSS) the browser should see the output of the parser (i.o.w., for XSS, don't assume that tokenizer output alone can tell you anything about whether the content does not contain JS). In general, whenever there's some parsing involved, the recommended approach to remove "badness" is to regenerate the well-formed output via the parser, instead of making checks and rejecting some inputs via tokenizing.

This was recently documented in https://pkg.go.dev/golang.org/x/net/html#hdr-Security_Considerations (we have had reported a similar bug recently). We know that there are HTML sanitizers in golang that rely on the tokenizer, and possibly these particular payloads would work under certain configurations - this would be a bug in those sanitizers that the tokenizer vs the parser.
{{< /blockquote >}}

## Let's revisit the documentation first though

Before we proceed further it's important to mention that the documentation at the time of reporting the finding mentioned the following thing:


{{< blockquote link="https://pkg.go.dev/golang.org/x/net@v0.9.0/html#hdr-Security_Considerations" >}}

Security Considerations

Care should be taken when parsing and interpreting HTML, whether full documents or fragments, within the framework of the HTML specification, especially with regard to untrusted inputs.

[...]

**If your use case requires semantically well-formed HTML, as defined by the WHATWG specification, the parser should be used rather than the tokenizer.**
{{< /blockquote >}}

## Reimplementing the `IsSafe` check using the Parser

Let's quickly change the implementation to use the parser rather than the Tokenizer to follow the documentation. 

```go
func IsSafe(content io.Reader) bool {
	parsed, err := html.ParseFragment(content, nil)
	if err != nil {
		return false
	}
	for _, el := range parsed {
		if !isNodeSafe(el) {
			return false
		}
	}
	return true
}

func isNodeSafe(node *html.Node) bool {
	if node == nil {
		return true
	}
	if len(node.Attr) != 0 {
		return false
	}
	if node.Type == html.ElementNode {
		// Parse and ParseFragment will inject html, head, and body. 
		// We'll allow these tags for the sake of simplicity, you'd normally want to filter them out.
		if node.Data != "strong" && node.Data != "html" && node.Data != "head" && node.Data != "body" {
			return false
		}
	}
	return isNodeSafe(node.NextSibling) && isNodeSafe(node.FirstChild)
}
```

```go
--- FAIL: TestIsSafe (0.00s)
    --- PASS: TestIsSafe/<strong>test</strong> (0.00s)
    --- PASS: TestIsSafe/<script>test</script> (0.00s)
    --- PASS: TestIsSafe/<script/>test (0.00s)
    --- PASS: TestIsSafe/<b>test</b> (0.00s)
    --- PASS: TestIsSafe/<strong_onclick="">test</strong> (0.00s)
    --- FAIL: TestIsSafe/<script_=">alert(1)</script> (0.00s)
FAIL
exit status 1
```

As we can see using the Parser in place of Tokenizer doesn't change the outcome. The code is still vulnerable.

## Appealing the response

At this point I thought the documentation needs changes as it's clearly dangerous. 

One thing to ponder: should unclear documentation be considered a security risk?

So I replied with the following:

{{< blockquote >}}
Thank you for the reply.

I only partially agree with the explanation provided.

The documentation for the html package states that it implements a html5-compliant Tokenizer and Parser. The tokenization/parsing specification is clearly defined behind https://html.spec.whatwg.org/multipage/parsing.html so any discrepancy between the implementation of html.Tokenizer/Parser and the specification should be fixed. The current implementation violates the state defined in https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state and more specifically how EQUALS SIGN (=) is handled.

Moreover, the same holds true for the Parser. As the Parser uses the Tokenizer that this issue was filed against, the input is parsed incorrectly (the script tag is not visible in the tree). The security considerations may suggest that just using the Parser without Rendering the result back may be enough to avoid this class of issues. The Parser is also unwieldy to use for this kind of purpose as it will return full html document with body and html tags, which are undesired and not reflective of what the user has provided.

Recently introduced Security Considerations seem to contradict the compliance of the parser/tokenizer and only shift the responsibility to consumers of the library rather than fixing the underlying issues.

[...]

I believe it's paramount that the parser/tokenizer remains compliant with the specification. Any slippage in this regard may result in unforeseen security issues.

In light of these considerations, I think the issues raised in the report should be reconsidered.

Thank you again for your reply and for your commitment to the development of the library.
{{< /blockquote  >}}

Google reopened the issue and assigned it a fairly high priority and severity:

{{< figure src="./reprioritization.png" alt="Google assigned it a P2/S2" align=center >}}

And followed up with the following reward ;)

{{< figure src="./reward.png" alt="An award of $0" align=center >}}

With the explanation below:

{{< blockquote >}}
After consulting with the Golang team, we believe there is no security issue here. The recommendation from the team is that if the tokenizer is to be used as a filtering mechanism (e.g. here - to reject XSS payloads), one should use the tokenizer output, and not the original input - in this case the tokenizer would not emit the script tag. Using it in a way that is presented in a POC can - and does - introduce a security issue, but the tokenizer is not at fault here.

Please note that the fact that this issue is not being rewarded does not mean that the product team won't fix the issue. We have filed a bug with the product team. They will review your report and decide if a fix is required. We'll let you know if the issue was fixed.
{{< /blockquote >}}

## Documentation Update

I found the initial explanation a bit unsatisfactory, not because I wasn't awarded any bounty, but because the documentation problem has been swept under the rug. Fortunately, a few days after the message was sent the repo saw the commit titled [html: another shot at security doc](https://github.com/golang/net/commit/eb1572ce7f7a6e97ec44c27568286345c2a7748e) where they added the following section:

```diff
+ In security contexts, if trust decisions are being made using the tokenized or
+ parsed content, the input must be re-serialized (for instance by using Render or
+ Token.String) in order for those trust decisions to hold, as the process of
+ tokenization or parsing may alter the content.
```

This wording is clear and concise - kudos to the team.

While the report was marked as fixed, the core issue was still not addressed.

## How to properly sanitize HTML

Instead of validating whether the input provided is safe or not, we should construct the HTML ourselves in the following manner.

```go
func Sanitize(content io.Reader) string {
	var builder strings.Builder
	tok := html.NewTokenizer(content)
	for {
		tt := tok.Next()
		token := tok.Token()
		switch tt {
		case html.StartTagToken, html.SelfClosingTagToken, html.EndTagToken:
			name := token.Data
			token.Attr = nil
			if name != "strong" {
				continue
			}
			builder.WriteString(token.String())
		case html.ErrorToken:
			return builder.String()
		case html.TextToken:
			builder.WriteString(token.String())
		default:
			continue
		}
	}
}
```

The [`Token.String()` method](https://github.com/golang/net/blob/d23d9bc549229fd1a9d375dc91141fcf1385d257/html/token.go#L100-L118) is much simpler and consistent, therefore much less prone to introducing security issues.


## The bug has been fixed!

A couple of months later I spotted an interesting looking commit in the `net/html` tree again:

{{< blockquote title="html: handle equals sign before attribute" link="https://github.com/golang/net/commit/4050002696905e240612ce01211f8ff46cc35afa" >}}
Apply the correct normalization when an equals sign appears before an
attribute name (e.g. '<tag =>' -> '<tag =="">'), per WHATWG 13.2.5.32.
{{< /blockquote >}}


```go
--- PASS: TestIsSafe (0.00s)
    --- PASS: TestIsSafe/<strong>test</strong> (0.00s)
    --- PASS: TestIsSafe/<script>test</script> (0.00s)
    --- PASS: TestIsSafe/<script/>test (0.00s)
    --- PASS: TestIsSafe/<b>test</b> (0.00s)
    --- PASS: TestIsSafe/<strong_onclick="">test</strong> (0.00s)
    --- PASS: TestIsSafe/<script_=">alert(1)</script> (0.00s)
PASS
ok      github.com/maciekmm/fuzz-net-http       0.002s
```


### ... or has it?

Let's run the fuzz test again after the fix was introduced:

```go
$ go test -fuzz=FuzzTokenize -run=^$
fuzz: elapsed: 0s, gathering baseline coverage: 0/434 completed
fuzz: elapsed: 0s, gathering baseline coverage: 434/434 completed, now fuzzing with 20 workers
fuzz: minimizing 37-byte failing input file
fuzz: elapsed: 0s, minimizing
--- FAIL: FuzzTokenize (0.30s)
    --- FAIL: FuzzTokenize (0.00s)
        lexbor_test.go:65: length mismatch: 
            lexbor      =[{Name:a Type:StartTag}], 
            net =[]
             not equal, input: <A/=">
```

It's fair to say the test suite in the library is not sufficient to catch those issues.

We hit a different edge case, but that's a story for another post. In short there's a [a report](https://github.com/golang/go/issues/63402) and [a PR](https://go-review.googlesource.com/c/net/+/533518) waiting to be merged.

# Conclusions

- Differential fuzzing is a powerful tool that can detect business logic issues or vulnerabilities.
- Documentation is a valuable resource, but it's essential to not follow it blindly. Validate and cross-check the information if you're working in a security-context.
- Any library including the standard library is most likely not bug-free. 
- When implementing any algorithm that is defined by a specification then that's what should be implemented. If it's a state machine make a state machine. Don't try to be smart.
- Whenever tokenizing any input, especially in security-critical contexts, it's best practice to re-serialize the input. This step ensures trust decisions remain valid. 

### Timeline

| Date         | Activity                                                |
|--------------|---------------------------------------------------------|
| Feb 26, 2023 | VRP report submission                                   |
| Mar 10, 2023 | Report status: Won't Fix                                |
| Mar 22, 2023 | Appeal initiated                                        |
| Apr 12, 2023 | Report closed once more                                 |
| Apr 29, 2023 | Documentation receives an update                        |
| Jun 20, 2023 | Fix introduced for EQUAL signs within attributes        |
| Oct 24, 2023 | Publication of this post after prolonged procrastination|

