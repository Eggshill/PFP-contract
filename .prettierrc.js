module.exports = {
  $schema: 'http://json.schemastore.org/prettierrc',
  semi: false,
  arrowParens: 'avoid',
  singleQuote: true,
  overrides: [
    {
      files: '*.sol',
      options: {
        printWidth: 120,
        useTabs: false,
        singleQuote: false,
        bracketSpacing: false,
        explicitTypes: 'always',
      },
    },
  ],
}
