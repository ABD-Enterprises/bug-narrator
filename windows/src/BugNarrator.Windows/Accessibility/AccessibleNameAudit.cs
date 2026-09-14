using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;

namespace BugNarrator.Windows.Accessibility;

/// <summary>
/// Walks a constructed window and reports every interactive control a screen reader would announce
/// without a usable name. The product spec's Accessibility Contract requires explicit labels for
/// controls that are not self-describing from visible text; this is the machine check for it.
///
/// Rules, per control type:
/// - Self-describing when their Content/Header is a non-empty string: Button, CheckBox, RadioButton,
///   TabItem, MenuItem, Hyperlink (its inline text).
/// - Never self-describing — typed or selected content is not a label: TextBox, PasswordBox,
///   ComboBox, ListBox, ListView, DatePicker, Slider. These need AutomationProperties.Name or a
///   LabeledBy pointing at an element with text.
/// - Any control whose Content is an image, an icon, an empty string, or a non-string object needs
///   AutomationProperties.Name.
///
/// Traversal uses the logical tree and descends explicitly into ContentControl.Content and
/// ItemsControl.Items when those are elements, so nested panels and constructed item containers are
/// reached without showing the window. Controls created only by templates at show time are out of
/// reach — a documented limit, not a pass.
/// </summary>
public static class AccessibleNameAudit
{
    private static readonly Type[] NeverSelfDescribing =
    [
        typeof(TextBox), typeof(PasswordBox), typeof(ComboBox), typeof(ListBox), typeof(ListView),
        typeof(DatePicker), typeof(Slider),
    ];

    public sealed record Violation(string WindowType, string ControlType, string Path)
    {
        public override string ToString() => $"{WindowType}: {ControlType} at {Path}";
    }

    public static IReadOnlyList<Violation> Run(Window window)
    {
        var violations = new List<Violation>();
        Walk(window, window.GetType().Name, window.GetType().Name, violations, new HashSet<object>(ReferenceEqualityComparer.Instance));
        return violations;
    }

    private static void Walk(object node, string windowType, string path, List<Violation> violations, HashSet<object> seen)
    {
        if (node is not DependencyObject dependencyObject || !seen.Add(node))
        {
            return;
        }

        if (node is Control control && IsInteractive(control) && !HasAccessibleName(control))
        {
            violations.Add(new Violation(windowType, control.GetType().Name, path));
        }

        // Hyperlink is a content element, not a Control, so it needs its own gate: named, or its
        // inlines carry text. An icon-only or empty link is announced as nothing.
        if (node is Hyperlink hyperlink
            && string.IsNullOrWhiteSpace(AutomationProperties.GetName(hyperlink))
            && string.IsNullOrWhiteSpace(TextOf(hyperlink)))
        {
            violations.Add(new Violation(windowType, nameof(Hyperlink), path));
        }

        var index = 0;
        foreach (var child in Children(dependencyObject))
        {
            Walk(child, windowType, $"{path}/{child.GetType().Name}[{index++}]", violations, seen);
        }
    }

    private static IEnumerable<object> Children(DependencyObject node)
    {
        foreach (var child in LogicalTreeHelper.GetChildren(node))
        {
            yield return child;
        }

        // Explicit content and items that are elements but not yet logical children (constructed
        // containers, content set before the parent was attached).
        if (node is ContentControl { Content: DependencyObject content })
        {
            yield return content;
        }

        if (node is HeaderedContentControl { Header: DependencyObject header })
        {
            yield return header;
        }

        if (node is ItemsControl items)
        {
            foreach (var item in items.Items.OfType<DependencyObject>())
            {
                yield return item;
            }
        }
    }

    private static bool IsInteractive(Control control)
    {
        // A TabControl or ListBox container is announced through its items; the items are checked individually.
        return control is ButtonBase or TextBoxBase or PasswordBox or ComboBox or ListBox or TabItem or MenuItem or DatePicker or Slider;
    }

    private static bool HasAccessibleName(Control control)
    {
        if (!string.IsNullOrWhiteSpace(AutomationProperties.GetName(control)))
        {
            return true;
        }

        if (AutomationProperties.GetLabeledBy(control) is { } label && !string.IsNullOrWhiteSpace(TextOf(label)))
        {
            return true;
        }

        if (NeverSelfDescribing.Any(type => type.IsInstanceOfType(control)))
        {
            return false;
        }

        return control switch
        {
            HeaderedContentControl headered => !string.IsNullOrWhiteSpace(TextOf(headered.Header)),
            ContentControl content => !string.IsNullOrWhiteSpace(TextOf(content.Content)),
            _ => false,
        };
    }

    /// <summary>Visible text of a content value: a string, a TextBlock, or a panel whose descendants are text.</summary>
    private static string? TextOf(object? value)
    {
        return value switch
        {
            null => null,
            string text => text,
            TextBlock block => string.IsNullOrEmpty(block.Text) ? string.Concat(block.Inlines.Select(TextOf)) : block.Text,
            Run run => run.Text,
            AccessText accessText => accessText.Text,
            Span span => string.Concat(span.Inlines.Select(TextOf)),
            InlineUIContainer container => TextOf(container.Child),
            Panel panel => string.Join(" ", panel.Children.OfType<object>().Select(TextOf).Where(text => !string.IsNullOrWhiteSpace(text))),
            ContentControl content => TextOf(content.Content),
            _ => null,
        };
    }
}
