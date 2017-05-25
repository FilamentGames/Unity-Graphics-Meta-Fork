﻿using UnityEngine.Graphing;

namespace UnityEngine.MaterialGraph
{
    [Title("UV/SphereWarpNode")]
    public class SphereWarpNode : AnyNode<SphereWarpNode.Definition>
    {
        public class Definition : IAnyNodeDefinition
        {
            public string name { get { return "SphereWarp"; } }

            public AnyNodeProperty[] properties
            {
                get
                {
                    return new AnyNodeProperty[]
                    {
                           // slotId is the 'immutable' value we used to connect things
                            new AnyNodeProperty { slotId= 0,    name = "inUVs",       description = "Input UV coords",          propertyType = PropertyType.Vector2,    value = Vector4.zero,                       state = AnyNodePropertyState.Slot },
                            new AnyNodeProperty { slotId= 1,    name = "center",      description = "UV radial center point",   propertyType = PropertyType.Vector2,    value= new Vector4(0.5f, 0.5f, 0.5f, 0.5f), state = AnyNodePropertyState.Constant },
                            new AnyNodeProperty { slotId= 2,    name = "warpAmount",  description = "Warp amount",              propertyType = PropertyType.Vector2,    value= Vector4.one,                         state = AnyNodePropertyState.Constant },
                            new AnyNodeProperty { slotId= 3,    name = "offset",      description = "UV offset",                propertyType = PropertyType.Vector2, value= Vector4.zero,                           state = AnyNodePropertyState.Constant },
                    };
                }
            }

            public AnyNodeSlot[] outputs
            {
                get
                {
                    return new AnyNodeSlot[]
                    {
                            new AnyNodeSlot { slotId= 4,    name = "outUVs", description = "Output UV texture coordinates", slotValueType = SlotValueType.Vector2, value = Vector4.zero  }
                    };
                }
            }

            public string hlsl
            {
                get
                {
                    return
                        "float2 delta = inUVs - center;\n" +
                        "float delta2 = dot(delta.xy, delta.xy);\n" +
                        "float delta4 = delta2 * delta2;\n" +
                        "float2 delta_offset = delta4 * warpAmount;\n" +
                        "outUVs = inUVs + delta * delta_offset + offset;";
                }
            }
        }
    }
}
