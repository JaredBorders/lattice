## Pull Request Standards

### Commit Message Standards

1. Commit messages are short and in present tense.
2. 👷🏻‍♂️ prefix -> commits related to adjusting/adding contract logic
3. ✅ prefix -> commits related to testing
4. 📚 prefix -> commits related to documentation
5. ✨ prefix -> commits related to linting/formatting
6. ⛳️ prefix -> commits related to optimizations
7. 🗑️ prefix -> commits related to removing code
8. 🪲 prefix -> commits related to fixing bugs
9. 🚀 prefix -> commits related to deployments/scripts
10. ⚙️ prefix -> commits related to configuration files (i.e., foundry.toml, makefile, etc)
11. 📸 prefix -> commits related to snapshots (i.e., lcov, gas, etc)
12. 🎭 prefix -> commits related to test mocks
13. ☂️ prefix -> commits related to CI
14. 🦌 prefix -> commits related to dependencies

### Pull Request Description Standards

Follow the below format for PR request descriptions:

```
{summary}

## Description
* Create
* Implement
* Remove
* Test
* etc...

## Related issue(s)
Closes [Issue](https://github.com/{USER}/{REPOSITORY}/{ISSUES}/{ID})

## Motivation and Context
Squashing bugs, adding features, etc...
```

## Checklist

Ensure you completed **all of the steps** below before submitting your pull request:

-   [ ] Ran `make test`?
-   [ ] Ran `make snap`?
-   [ ] Ran `make lint`?

👎 _Pull requests with an incomplete checklist will be thrown out_ 👎
