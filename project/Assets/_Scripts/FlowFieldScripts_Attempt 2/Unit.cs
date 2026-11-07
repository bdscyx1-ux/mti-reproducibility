using System.Collections;
using System.Collections.Generic;
using UnityEngine;

//****************************************************************************************************//
//All the comments in this script were abandoned codes. They were abandonded during the debug process.//
//****************************************************************************************************//

public class Unit : MonoBehaviour
{
    public float moveSpeed;
    public float avoidanceRadius = 0.1f;
    public LayerMask unitMask;
    public float smoothTime = 0.01f;
    //public bool TargetReached = false;
    //public int destinationRadius; //New destination under this radius
    //public Vector3 Destination;

    public Rigidbody rb;
    private Collider unitCollider;
    private FlowField currentFlowField;
    private Vector3 moveDirection;
    //private Vector3 moveDirectionAvoidance;
    private Vector3 smoothMoveDirection;
    private Vector3 moveDirectionVelocity = Vector3.zero;
    private GridController gridController;
    private UnitController unitController;
    public Cell targetCell;
    private Cell cellBelow;
    private Vector3 unitPosFlat;
    public bool isMovingToTarget = false;
    //private bool needAvoidance = false;
    private float gravityMultiplier = 10f;
    private Vector3 targetCellWorldPos;
    //private bool reachedTargetCell = false;

    public float stoppingDistance = 1.5f;
    public float collisionSeparationForce = 200f;

    private void Awake()
    {
        unitCollider = GetComponent<Collider>();
        rb = GetComponent<Rigidbody>();
        if (rb == null)
        {
            rb = gameObject.AddComponent<Rigidbody>();
            rb.useGravity = false;
        }
        rb.isKinematic = false;
        rb.constraints = RigidbodyConstraints.FreezeRotation;
        rb.mass = 1f;
        rb.drag = 10f;
        rb.angularDrag = 10f;
        rb.constraints = RigidbodyConstraints.FreezeRotation; 

        gridController = FindObjectOfType<GridController>();
    }

    public void SetDestinationGrid(Vector2Int gridPosition)
    {
        targetCell = gridController.curFlowField.grid[gridPosition.x, gridPosition.y];
        Debug.Log("SetDestinationGrid called");
        Debug.Log($"New targetCell is :[{targetCell.gridIndex.x}, {targetCell.gridIndex.y}]");
        isMovingToTarget = true;
    }

    private void FixedUpdate()
    {
        //stoppingDistance = 1.5f;
        //Destination = gridController.destinationCell.worldPos;
        //if (Vector3.Distance(transform.position, Destination) < stoppingDistance)
        //{
        //    TargetReached = true;
        //    Debug.Log("Target Reached");
        //}
        //if (!TargetReached)
        //{
        if (gridController == null || gridController.curFlowField == null)
        {
            return;
        }

        cellBelow = gridController.curFlowField.GetCellFromWorldPos(transform.position);

        if (isMovingToTarget && targetCell != null) 
        {
            //float distance = Vector3.Distance(transform.position, targetCell.worldPos);
            //GetComponent<CapsuleCollider>().enabled = false;
            //Debug.Log($"Distance to target cell: {distance}");

            //if (transform.position == targetCellWorldPos)
            //{
            //    rb.velocity = Vector3.zero;
            //    rb.isKinematic = true;
            //    isMovingToTarget = false;
            //    //reachedTargetCell = true;
            //    //Debug.Log("Reached new target cell");
            //    return;
            //}
            targetCellWorldPos = new Vector3(targetCell.worldPos.x, 16, targetCell.worldPos.z);
            moveDirection = (targetCell.worldPos - transform.position).normalized;
        }
        else
        {
            //GetComponent<CapsuleCollider>().enabled = true;
            rb.isKinematic = false;
            moveDirection = new Vector3(cellBelow.bestDirection.Vector.x, 0, cellBelow.bestDirection.Vector.y);
            //Debug.Log("Moving along flow field");
            //AvoidObstacles();
        }

        rb.velocity = moveDirection * moveSpeed;
    }

    private void Update()
    {
        if (targetCell != null)
        {
            if (Input.GetMouseButtonDown(1))
            {
                targetCell = null;
                isMovingToTarget = false;
            }
        }
    }



    //**********************************************************************************************************************************//
    //This part of abandonded codes were used to make the units stop when they reach the destination point, applied in the FixedUpdate()//
    //**********************************************************************************************************************************//

    //**********************************************************************************************************************************//
    //**********************************************************************************************************************************//
    //if (isMovingToTarget)
    //{
    //    moveDirection = (targetCell.worldPos - transform.position).normalized;
    //    ApplyAvoidanceForces();
    //}
    //if(!isMovingToTarget && reachedTargetCell && Input.GetMouseButtonDown(1) || !isMovingToTarget && !reachedTargetCell)
    //{
    //    rb.isKinematic = false;
    //    moveDirection = new Vector3(cellBelow.bestDirection.Vector.x, 0, cellBelow.bestDirection.Vector.y);
    //}

    //smoothMoveDirection = Vector3.SmoothDamp(smoothMoveDirection, moveDirection, ref moveDirectionVelocity, smoothTime);


    //rb.AddForce(Vector3.down * gravityMultiplier, ForceMode.Acceleration);

    //if (isMovingToTarget && targetCell != null && Vector3.Distance(transform.position, targetCell.worldPos) <= stoppingDistance)
    //{
    //    rb.velocity = Vector3.zero;
    //    isMovingToTarget = false;
    //    Debug.Log(isMovingToTarget);
    //    Debug.Log("Reached new target cell");
    //    return;
    //}

    //if (isMovingToTarget)
    //{
    //    moveDirection = (targetCell.worldPos - transform.position).normalized;
    //    AvoidOtherUnits();
    //}
    //else
    //{
    //    moveDirection = new Vector3(cellBelow.bestDirection.Vector.x, 0, cellBelow.bestDirection.Vector.y); 
    //}

    //if (Input.GetMouseButtonDown(1))
    //{
    //    rb.isKinematic = false;
    //    //moveDirection = new Vector3(cellBelow.bestDirection.Vector.x, 0, cellBelow.bestDirection.Vector.y);
    //}

    //rb.isKinematic = false;

    //rb.velocity = moveDirection * moveSpeed;

    //if (Input.GetKey(KeyCode.Alpha4))
    //{
    //    Debug.Log("Ready to adjust");
    //    if (targetCell != null)
    //    {
    //        moveDirection = (targetCell.worldPos - transform.position).normalized;
    //        rb.isKinematic = false;
    //        rb.velocity = moveDirection * moveSpeed;
    //        AvoidOtherUnits();
    //        //ApplyAvoidanceForces();
    //        Debug.Log($"moving to :[{targetCell.gridIndex.x}, {targetCell.gridIndex.y}]");
    //        Debug.Log($"Move Direction: {targetCell.worldPos}");
    //        isMovingToTarget = true;
    //    }
    //    //TargetReached = true;
    //    //moveDirectionAvoidance = (targetCell.worldPos - transform.position).normalized;
    //    //rb.isKinematic = false;
    //    //rb.velocity = moveDirectionAvoidance * moveSpeed;    
    //}

    //if (Input.GetKeyUp(KeyCode.Alpha4))
    //{
    //    Debug.Log("Alpha4 key released");
    //    rb.velocity = Vector3.zero;
    //    rb.isKinematic = true; // 设置为运动学，停止所有运动
    //    isMovingToTarget = false; // 停止移动
    //}

    //}
    //else
    //{

    //rb.isKinematic = true;

    //if (Input.GetMouseButtonDown(1))
    //    {
    //        //rb.isKinematic = false;
    //        //TargetReached = false;
    //        return;
    //    }
    //    //Debug.Log("Target Reached");
    ////} 


    //**********************************************************************************************************************************//
    //**********************************************************************************************************************************//


    //*******************************************************************************************************************************************************//
    //This part of abandonded codes were used to detect collision among units, trying to split them in case they gathered as a group and cannot move anymore.// 
    //*******************************************************************************************************************************************************//

    //*******************************************************************************************************************************************************//
    //*******************************************************************************************************************************************************//


    //private void OnCollisionStay(Collision collision)
    //{
    //    if (targetCell != null)
    //    {
    //        if (collision.gameObject.layer == 6)
    //        {
    //            Debug.Log($"Target Cell is: {targetCell.gridIndex}");
    //            Debug.Log(isMovingToTarget);
    //            moveDirection = (transform.position - targetCell.worldPos).normalized;
    //            //Vector3 separationForce = (transform.position - collision.transform.position) * 10;
    //            //rb.AddForce(separationForce.normalized * collisionSeparationForce, ForceMode.Impulse);

    //            //Rigidbody otherRb = collision.gameObject.GetComponent<Rigidbody>();
    //            //if (otherRb != null)
    //            //{
    //            //    otherRb.AddForce(-separationForce.normalized * collisionSeparationForce, ForceMode.Impulse);
    //            //    Debug.Log("Is adding force to avoid");
    //            //}
    //            //AvoidOtherUnits();
    //        }

    //    }
    //}



    //private void OnCollisionStay(Collision collision)
    //{
    //    if (targetCell != null)
    //    {

    //        //Debug.Log("Collide");

    //        if (collision.gameObject.layer == LayerMask.NameToLayer("PlayerUnits"))
    //        {
    //            Debug.Log($"Collide with other: {unitMask}");
    //            ApplyAvoidanceForces();
    //        }
    //    }
    //}

    //public void SpreadOut()
    //{
    //    Debug.Log("Ready to adjust");
    //    if (targetCell != null)
    //    {
    //        moveDirection = (targetCell.worldPos - transform.position).normalized;
    //        rb.isKinematic = false;
    //        rb.velocity = moveDirection * moveSpeed;
    //        ApplyAvoidanceForces();
    //        Debug.Log($"moving to :[{targetCell.gridIndex.x}, {targetCell.gridIndex.y}]");
    //        Debug.Log($"Move Direction: {targetCell.worldPos}");
    //    }
    //}

    private void AvoidObstacles()
    {
        Collider[] nearbyUnits = Physics.OverlapSphere(transform.position, avoidanceRadius, 8);

        Vector3 avoidanceForce = Vector3.zero;
        foreach (Collider unit in nearbyUnits)
        {
            if (unit.gameObject != gameObject)
            {
                Vector3 toOther = transform.position - unit.transform.position;
                if (toOther.magnitude < avoidanceRadius)
                {
                    avoidanceForce += toOther.normalized / toOther.magnitude;
                    Debug.Log("Collide with obstacle");
                }
            }
        }

        if (avoidanceForce != Vector3.zero)
        {
            moveDirection += avoidanceForce;
            moveDirection.Normalize();
        }
    }

    //private void SetKinematic()
    //{
    //    rb.isKinematic = true;
    //}

    //*******************************************************************************************************************************************************//
    //*******************************************************************************************************************************************************//
}
