using System.Collections;
using System.Collections.Generic;
using Unity.VisualScripting;
using UnityEngine;

//****************************************************************************************************//
//All the comments in this script were abandoned codes. They were abandonded during the debug process.//
//****************************************************************************************************//

public class UnitController : MonoBehaviour
{
    public GridController gridController;
    public GameObject unitPrefab;
    public int numUnitsPerSpawn;

    private Vector3 destinationWorldPos;
    private Vector2Int destinationGridPos;
    //private HashSet<Vector2Int> occupiedCells; 
    public bool[,] occupiedCells; //Record occupied cells

    public List<GameObject> unitsInGame;

    private void Awake()
    {
        unitsInGame = new List<GameObject>();
        occupiedCells = new bool[gridController.gridSize.x, gridController.gridSize.y];
    }

    void Update()
    {
        if (Input.GetKeyDown(KeyCode.Alpha1))
        {
            if(unitsInGame.Count < 400)
            {
                SpawnUnits();
            }
            else
            {
                return;
            }
        }

        if (Input.GetKeyDown(KeyCode.Alpha2))
        {
            DestroyUnits();
        }

        //if (Input.GetKeyDown(KeyCode.Alpha3))
        //{
        //    //destinationWorldPos = gridController.destinationCell.worldPos;
        //    destinationGridPos = new Vector2Int(gridController.destinationCell.gridIndex.x, gridController.destinationCell.gridIndex.y);
        //    SetUnitsDestinationGrid(destinationGridPos);
        //    Debug.Log("3 Pressed");
        //}
    }

    //private void FixedUpdate()
    //{
    //    if (Input.GetKeyDown(KeyCode.Alpha3))
    //    {
    //        destinationWorldPos = gridController.destinationCell.worldPos;
    //        destinationGridPos = new Vector2Int(gridController.destinationCell.gridIndex.x, gridController.destinationCell.gridIndex.y);
    //        SetUnitsDestinationGrid(destinationGridPos, destinationWorldPos);
    //        Debug.Log("3 Pressed");
    //    }
    //}

    public void UnitFormation()
    {
        destinationGridPos = new Vector2Int(gridController.destinationCell.gridIndex.x, gridController.destinationCell.gridIndex.y);
        SetUnitsDestinationGrid(destinationGridPos);
    }

    private void SpawnUnits()
    {
        Vector3 mousePos = GetMouseWorldPosition();
        if (mousePos == Vector3.zero) return;

        float spawnRadius = 1.0f; 

        int colMask = LayerMask.GetMask("Impassible", "PlayerUnits");

        Vector3 newPos;
        for (int i = 0; i < numUnitsPerSpawn; i++)
        {
            GameObject newUnit = Instantiate(unitPrefab);
            newUnit.transform.parent = transform;
            unitsInGame.Add(newUnit);

            do
            {
                newPos = new Vector3(
                    mousePos.x + Random.Range(-spawnRadius, spawnRadius),
                    0,
                    mousePos.z + Random.Range(-spawnRadius, spawnRadius)
                );
                newUnit.transform.position = newPos;
            }
            while (Physics.OverlapSphere(newPos, 0.25f, colMask).Length > 0);
        }
    }

    private Vector3 GetMouseWorldPosition()
    {
        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
        if (Physics.Raycast(ray, out RaycastHit hit))
        {
            return hit.point;
        }
        return Vector3.zero;
    }

    private void DestroyUnits()
    {
        foreach (GameObject go in unitsInGame)
        {
            Destroy(go);
        }
        unitsInGame.Clear();
        occupiedCells = new bool[gridController.gridSize.x, gridController.gridSize.y];
    }

    private void SetUnitsDestinationGrid(Vector2Int destinationGridPosition)
    {
        int unitsCount = unitsInGame.Count;
        int matrixSize = Mathf.CeilToInt(Mathf.Sqrt(unitsCount));

        if (matrixSize * matrixSize < unitsCount)
        {
            matrixSize++;
            Debug.Log($"The matrix size square is {Mathf.Pow(matrixSize, 2f)}");
        }

        AssignUnitsToGrid(unitsInGame, destinationGridPosition, -matrixSize / 2, matrixSize / 2, -matrixSize / 2, matrixSize / 2);
    }

    private void AssignUnitsToGrid(List<GameObject> units, Vector2Int destinationGridPosition, int startXOffset, int endXOffset, int startYOffset, int endYOffset)
    {
        int unitIndex = 0;

        for (int x = startXOffset; x <= endXOffset; x++)
        {
            for (int y = startYOffset; y <= endYOffset; y++)
            {
                if (unitIndex >= units.Count) break;  

                Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
                if (IsValidGridPosition(targetGridPosition))
                {
                    GameObject unit = units[unitIndex];
                    Unit unitScript = unit.GetComponent<Unit>();
                    if (unitScript != null)
                    {
                        unitScript.SetDestinationGrid(targetGridPosition);
                        occupiedCells[targetGridPosition.x, targetGridPosition.y] = true; 
                        Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
                        unitIndex++;
                    }
                    
                }
            }
            if (unitIndex >= units.Count) break;
        }
    }

    //private void SetUnitsDestinationGrid(Vector2Int destinationGridPosition, Vector3 destinationWorldPosition)
    //{
    //    int unitsCount = unitsInGame.Count;
    //    int matrixSize = Mathf.CeilToInt(Mathf.Sqrt(unitsCount));

    //    if (matrixSize * matrixSize < unitsCount)
    //    {
    //        matrixSize++;
    //        Debug.Log($"The matrix size square is {Mathf.Pow(matrixSize, 2f)}");
    //    }
    //    int halfMatrixSize = matrixSize / 2;

    //    List<GameObject> leftTopUnits = new List<GameObject>();
    //    List<GameObject> leftBottomUnits = new List<GameObject>();
    //    List<GameObject> rightTopUnits = new List<GameObject>();
    //    List<GameObject> rightBottomUnits = new List<GameObject>();

    //    // Assign Units to Left, Right, Up, Down
    //    foreach (GameObject unit in unitsInGame)
    //    {
    //        if (unit.transform.position.x < destinationWorldPosition.x)
    //        {
    //            if (unit.transform.position.z < destinationWorldPosition.z)
    //            {
    //                leftBottomUnits.Add(unit);
    //            }
    //            else
    //            {
    //                leftTopUnits.Add(unit);
    //            }
    //        }
    //        else
    //        {
    //            if (unit.transform.position.z < destinationWorldPosition.z)
    //            {
    //                rightBottomUnits.Add(unit);
    //            }
    //            else
    //            {
    //                rightTopUnits.Add(unit);
    //            }
    //        }
    //    }



    //AssignUnitsToGrid(leftTopUnits, destinationGridPosition, -halfMatrixSize, 0, 0, halfMatrixSize);


    //AssignUnitsToGrid(leftBottomUnits, destinationGridPosition, -halfMatrixSize, 0, -halfMatrixSize, 0);


    //AssignUnitsToGrid(rightTopUnits, destinationGridPosition, 0, halfMatrixSize, 0, halfMatrixSize);


    //AssignUnitsToGrid(rightBottomUnits, destinationGridPosition, 0, halfMatrixSize, -halfMatrixSize, 0);
//}


    //private void AssignUnitsToGrid(List<GameObject> units, Vector2Int destinationGridPosition, Vector2Int startOffset, Vector2Int endOffset)
    //{
    //    
    //    int unitIndex = 0;
    //    for (int x = -halfMatrixSize; x <= 0; x++)
    //    {
    //        for (int y = 0; y <= halfMatrixSize; y++)
    //        {
    //            if (unitIndex >= leftTopUnits.Count) break;

    //            Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
    //            if (IsValidGridPosition(targetGridPosition))
    //            {
    //                GameObject unit = leftTopUnits[unitIndex];
    //                Unit unitScript = unit.GetComponent<Unit>();
    //                if (unitScript != null)
    //                {
    //                    unitScript.SetDestinationGrid(targetGridPosition);
    //                    Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
    //                }
    //                unitIndex++;
    //            }
    //        }
    //        if (unitIndex >= leftTopUnits.Count) break;
    //    }

    //    
    //    unitIndex = 0;
    //    for (int x = -halfMatrixSize; x <= 0; x++)
    //    {
    //        for (int y = -halfMatrixSize; y <= 0; y++)
    //        {
    //            if (unitIndex >= leftBottomUnits.Count) break;

    //            Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
    //            if (IsValidGridPosition(targetGridPosition))
    //            {
    //                GameObject unit = leftBottomUnits[unitIndex];
    //                Unit unitScript = unit.GetComponent<Unit>();
    //                if (unitScript != null)
    //                {
    //                    unitScript.SetDestinationGrid(targetGridPosition);
    //                    Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
    //                }
    //                unitIndex++;
    //            }
    //        }
    //        if (unitIndex >= leftBottomUnits.Count) break;
    //    }

    //    
    //    unitIndex = 0;
    //    for (int x = 0; x <= halfMatrixSize; x++)
    //    {
    //        for (int y = 0; y <= halfMatrixSize; y++)
    //        {
    //            if (unitIndex >= rightTopUnits.Count) break;

    //            Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
    //            if (IsValidGridPosition(targetGridPosition))
    //            {
    //                GameObject unit = rightTopUnits[unitIndex];
    //                Unit unitScript = unit.GetComponent<Unit>();
    //                if (unitScript != null)
    //                {
    //                    unitScript.SetDestinationGrid(targetGridPosition);
    //                    Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
    //                }
    //                unitIndex++;
    //            }
    //        }
    //        if (unitIndex >= rightTopUnits.Count) break;
    //    }

    //    
    //    unitIndex = 0;
    //    for (int x = 0; x <= halfMatrixSize; x++)
    //    {
    //        for (int y = -halfMatrixSize; y <= 0; y++)
    //        {
    //            if (unitIndex >= rightBottomUnits.Count) break;

    //            Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
    //            if (IsValidGridPosition(targetGridPosition))
    //            {
    //                GameObject unit = rightBottomUnits[unitIndex];
    //                Unit unitScript = unit.GetComponent<Unit>();
    //                if (unitScript != null)
    //                {
    //                    unitScript.SetDestinationGrid(targetGridPosition);
    //                    Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
    //                }
    //                unitIndex++;
    //            }
    //        }
    //        if (unitIndex >= rightBottomUnits.Count) break;
    //    }
    //}

    private bool IsValidGridPosition(Vector2Int gridPosition)
    {
        return gridPosition.x >= 0 && gridPosition.x < gridController.gridSize.x &&
               gridPosition.y >= 0 && gridPosition.y < gridController.gridSize.y;
    }

    //private void SetUnitsDestinationGrid(Vector2Int destinationGridPosition, Vector3 destinationWorldPosition)
    //{
    //    int unitsCount = unitsInGame.Count;
    //    int halfMatrixSize = matrixSize / 2;
    //    List<GameObject> leftUnits = new List<GameObject>();
    //    List<GameObject> rightUnits = new List<GameObject>();

    //    // Assign Units to left and right side separately
    //    foreach (GameObject unit in unitsInGame)
    //    {
    //        if (unit.transform.position.x < destinationWorldPosition.x)
    //        {
    //            leftUnits.Add(unit);
    //        }
    //        else
    //        {
    //            rightUnits.Add(unit);
    //        }
    //    }

    //    // Assign Units on the left side to left matrix
    //    int unitIndex = 0;
    //    for (int x = -halfMatrixSize; x <= 0; x++)
    //    {
    //        for (int y = -halfMatrixSize; y <= halfMatrixSize; y++)
    //        {
    //            if (unitIndex >= leftUnits.Count) break;

    //            Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
    //            if (IsValidGridPosition(targetGridPosition))
    //            {
    //                GameObject unit = leftUnits[unitIndex];
    //                Unit unitScript = unit.GetComponent<Unit>();
    //                if (unitScript != null)
    //                {
    //                    unitScript.SetDestinationGrid(targetGridPosition);
    //                    Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
    //                }
    //                unitIndex++;
    //            }
    //        }
    //        if (unitIndex >= leftUnits.Count) break;
    //    }

    //    // Assign Units on the right side to right matrix
    //    unitIndex = 0;
    //    for (int x = 1; x <= halfMatrixSize; x++)
    //    {
    //        for (int y = -halfMatrixSize; y <= halfMatrixSize; y++)
    //        {
    //            if (unitIndex >= rightUnits.Count) break;

    //            Vector2Int targetGridPosition = new Vector2Int(destinationGridPosition.x + x, destinationGridPosition.y + y);
    //            if (IsValidGridPosition(targetGridPosition))
    //            {
    //                GameObject unit = rightUnits[unitIndex];
    //                Unit unitScript = unit.GetComponent<Unit>();
    //                if (unitScript != null)
    //                {
    //                    unitScript.SetDestinationGrid(targetGridPosition);
    //                    Debug.Log($"Setting destination for unit: {unit.name} to grid position: {targetGridPosition}");
    //                }
    //                unitIndex++;
    //            }
    //        }
    //        if (unitIndex >= rightUnits.Count) break;
    //    }
    //}
}
