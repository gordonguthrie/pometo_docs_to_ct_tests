# Pometo Docs To CT Tests Rebar3 Plugin


Builds common tests from `Pometo` markdown documentation

Build
-----

    $ rebar3 compile

Use
---

Add the plugin to your rebar config:

    {plugins, [
        {pometo_docs_to_tests, {git, "https://github.com/gordonguthrie/pometo_docs_to_ct_tests"}}
    ]}.

Then just call your plugin directly in an existing application:


    $ rebar3 pometo_docs_to_ct_tests
    ===> Fetching pometo_docs_to_ct_tests
    ===> Compiling pometo_docs_to_ct_tests
    <Plugin Output>
