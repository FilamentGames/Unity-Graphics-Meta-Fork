﻿using System.Collections.Generic;
using GtfPlayground.DataModel;
using GtfPlayground.GraphElements;
using UnityEditor;
using UnityEditor.GraphToolsFoundation.Overdrive;
using UnityEditor.GraphToolsFoundation.Overdrive.BasicModel;
using UnityEngine.GraphToolsFoundation.Overdrive;
using UnityEngine.UIElements;

namespace GtfPlayground
{
    [GraphElementsExtensionMethodsCache(100)]
    public static class PlaygroundUIFactoryExtensions
    {
        public static IModelUI CreateConnectionInfoNode(this ElementBuilder elementBuilder, CommandDispatcher store,
            ConnectionInfoNodeModel model)
        {
            var ui = new ConnectionInfoNode();
            ui.SetupBuildAndUpdate(model, store, elementBuilder.GraphView, elementBuilder.Context);
            return ui;
        }

        public static IModelUI CreateDataNode(this ElementBuilder elementBuilder, CommandDispatcher store,
            DataNodeModel model)
        {
            var ui = new DataNode();
            ui.SetupBuildAndUpdate(model, store, elementBuilder.GraphView, elementBuilder.Context);
            return ui;
        }

        public static IModelUI CreateConversionEdge(this ElementBuilder elementBuilder, CommandDispatcher store,
            ConversionEdgeModel model)
        {
            var ui = new ConversionEdge();
            ui.SetupBuildAndUpdate(model, store, elementBuilder.GraphView, elementBuilder.Context);
            return ui;
        }

        public static IModelUI CreateCustomizableNode(this ElementBuilder elementBuilder, CommandDispatcher store,
            CustomizableNodeModel model)
        {
            var ui = new CustomizableNode();
            ui.SetupBuildAndUpdate(model, store, elementBuilder.GraphView, elementBuilder.Context);
            return ui;
        }

        public static IModelUI CreatePort(this ElementBuilder elementBuilder, CommandDispatcher store,
            PortModel model)
        {
            var ui = (Port)DefaultFactoryExtensions.CreatePort(elementBuilder, store, model);
            ui.styleSheets.Add(AssetDatabase.LoadAssetAtPath<StyleSheet>(
                "Packages/com.unity.shadergraph/Editor/Exploration/Stylesheets/PlaygroundPorts.uss"));
            return ui;
        }

        public static VisualElement CreateCustomTypeEditor(this IConstantEditorBuilder editorBuilder,
            DayOfWeekConstant c)
        {
            var dropdown = new DropdownField(
                new List<string>(DayOfWeekConstant.Names),
                DayOfWeekConstant.Values.IndexOf(c.Value)
            );
            dropdown.RegisterValueChangedCallback(_ => { c.Value = DayOfWeekConstant.Values[dropdown.index]; });

            var root = new VisualElement();
            root.Add(dropdown);

            return root;
        }
    }
}
