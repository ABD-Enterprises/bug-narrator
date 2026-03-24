// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'BugNarrator Docs',
  tagline: 'User, release, and roadmap documentation for BugNarrator',
  favicon: 'img/favicon.png',
  url: 'https://deffenda.github.io',
  baseUrl: '/bugnarrator/',
  organizationName: 'deffenda',
  projectName: 'bugnarrator',
  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw'
    }
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en']
  },
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js')
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css')
        }
      }
    ]
  ],
  themeConfig: {
    navbar: {
      title: 'BugNarrator Docs',
      items: [
        {
          type: 'doc',
          docId: 'intro',
          label: 'Docs',
          position: 'left'
        },
        {
          href: 'https://github.com/deffenda/bugnarrator',
          label: 'GitHub',
          position: 'right'
        }
      ]
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            { label: 'Intro', to: '/' },
            { label: 'Getting Started', to: '/onboarding/getting-started' },
            { label: 'User Manual', to: '/user/user-manual' },
            { label: 'Product Spec', to: '/architecture/product-spec' }
          ]
        },
        {
          title: 'Maintainers',
          items: [
            { label: 'Release Process (Repo)', href: 'https://github.com/deffenda/bugnarrator/blob/main/docs/release/release-process.md' },
            { label: 'Roadmap (Repo)', href: 'https://github.com/deffenda/bugnarrator/blob/main/docs/roadmap/roadmap.md' }
          ]
        }
      ],
      copyright: `Copyright © ${new Date().getFullYear()} BugNarrator`
    }
  }
};

module.exports = config;
