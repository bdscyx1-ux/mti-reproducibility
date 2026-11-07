using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class GridController : MonoBehaviour
{
    public Vector2Int gridSize;
    public float cellRadius = 0.5f;
    public FlowField curFlowField;
    public GridDebug gridDebug;
    public Cell destinationCell;
    public Unit unit;
    public UnitController unitController;


    private void InitializeFlowField()
    {
        curFlowField = new FlowField(cellRadius, gridSize);
        curFlowField.CreateGrid();
        gridDebug.SetFlowField(curFlowField);
    }

    private void Update()
    {
        if (Input.GetMouseButtonDown(1))
        {
            InitializeFlowField();

            curFlowField.CreateCostField();
            
            Vector3 worldMousePos = GetMouseWorldPosition();
            destinationCell = curFlowField.GetCellFromWorldPos(worldMousePos);

            curFlowField.CreateIntegrationField(destinationCell);

            curFlowField.CreateFlowField();

            gridDebug.DrawFlowField();
        }
    }

    Vector3 GetMouseWorldPosition()
    {
        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
        if (Physics.Raycast(ray, out RaycastHit hit))
        {
            return hit.point;
        }
        return Vector3.zero;
    }
}
