// Output Type: Mesh

bool GetMeshAndElementIndex(inout AttributesMesh input, inout AttributesElement element)
{
    uint index = input.instanceID;

    if (ShouldCullElement(index))
        return false;

    #if VFX_HAS_INDIRECT_DRAW
    index = indirectBuffer[index];
    #endif

    element.index = index;

    // Mesh requires no preliminary configuration.
    return true;
}
