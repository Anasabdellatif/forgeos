# Design System

This document defines reusable interface standards for projects using this blueprint. Replace TBD values with project-specific choices when a real product adopts the blueprint.

## Experience Principles

- Prioritize the user's primary workflow over decorative content.
- Keep navigation predictable and information hierarchy clear.
- Make permissions, state, validation, and errors visible without exposing sensitive details.
- Prefer consistency over novelty for repeated business workflows.

## Foundations

- Brand: TBD.
- Typography: TBD.
- Color system: TBD, including accessible contrast requirements.
- Spacing and layout scale: TBD.
- Icon system: TBD.
- Motion: use only when it clarifies state or feedback.

## Components

Document reusable rules for:

- Buttons and icon buttons.
- Forms, validation messages, and destructive confirmations.
- Cards and panels.
- Tables, pagination, sorting, filtering, export, and row actions.
- Search and command surfaces.
- Navigation, breadcrumbs, tabs, and sidebars.
- Modals, drawers, toasts, banners, and alerts.
- File uploads and previews.

## Required States

Each user-facing workflow should define applicable states:

- Loading.
- Empty.
- Error.
- Permission denied.
- Validation failed.
- Saving or processing.
- Success or completion.

## Accessibility

- Define target WCAG level: TBD.
- Ensure keyboard access for interactive controls.
- Provide visible focus states.
- Use semantic labels and accessible names.
- Do not communicate critical meaning through color alone.

## Responsive Behavior

- Define supported viewport and device classes: TBD.
- Keep primary actions reachable on small screens.
- Avoid horizontal overflow except for intentionally scrollable data grids.
- Test critical workflows on mobile and desktop.

## Content Guidelines

- Use clear action labels.
- Prefer domain language from `docs/domains/domain-map.md`.
- Avoid exposing implementation details in user-facing errors.
- Keep destructive and irreversible actions explicit.

## Maintenance

Update this file when introducing reusable UI patterns, changing accessibility targets, or changing product-wide interaction standards.
