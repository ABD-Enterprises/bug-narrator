using System.Collections.Generic;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace BugNarrator.Windows.Accessibility;

/// <summary>
/// The views build every input as "label TextBlock, then the input" inside a panel. This associates
/// each unlabeled input with the TextBlock immediately before it through
/// <see cref="AutomationProperties.LabeledByProperty"/>, so the visible label is also what a screen
/// reader announces — the same thing a sighted user reads. An input that already carries a Name or
/// LabeledBy is left alone, and an input with no preceding text sibling stays unlabeled for the
/// audit to report; this is not a way to silence it.
/// </summary>
public static class AccessibleLabels
{
    public static void LabelInputsFromPrecedingText(DependencyObject root)
    {
        foreach (var panel in Panels(root))
        {
            // Strictly the immediately preceding sibling, consumed once: a label names the one input
            // that follows it. A hint, a button, or a second input in between breaks the pairing, so a
            // stale label can never be attached to an unrelated input and pass the audit by accident.
            UIElement? previous = null;
            foreach (UIElement child in panel.Children)
            {
                if (child is TextBox or PasswordBox or ComboBox or ListBox or DatePicker
                    && previous is TextBlock { Text: var text } label
                    && !string.IsNullOrWhiteSpace(text)
                    && string.IsNullOrWhiteSpace(AutomationProperties.GetName(child))
                    && AutomationProperties.GetLabeledBy(child) is null)
                {
                    AutomationProperties.SetLabeledBy(child, label);
                }

                previous = child;
            }
        }
    }

    private static IEnumerable<Panel> Panels(DependencyObject node)
    {
        if (node is Panel panel)
        {
            yield return panel;
        }

        foreach (var child in LogicalTreeHelper.GetChildren(node))
        {
            if (child is DependencyObject dependencyObject)
            {
                foreach (var nested in Panels(dependencyObject))
                {
                    yield return nested;
                }
            }
        }

        if (node is ContentControl { Content: DependencyObject content })
        {
            foreach (var nested in Panels(content))
            {
                yield return nested;
            }
        }
    }
}
