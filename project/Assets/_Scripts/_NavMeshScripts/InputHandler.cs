using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using CY.DDMFinal.Player;


namespace CY.DDMFinal.InputManager
{
    public class InputHandler : MonoBehaviour
    {
        public static InputHandler instance;
        public GameObject unitPrefab;

        private RaycastHit hit;
        private List<Transform> selectedUnits = new List<Transform>();
        private bool isDragging = false;
        private Vector3 mousePos;

        // Start is called before the first frame update
        void Start()
        {
            instance = this;
        }

        // Update is called once per frame
        void Update()
        {
            HandleUnitMovement();
        }

        private void OnGUI()
        {
            if (isDragging)
            {
                Rect rect = MultiSelection.GetScreenRect(mousePos, Input.mousePosition);
                MultiSelection.DrawScreenRect(rect, new Color(0f, 0f, 0f, 0.25f));
                MultiSelection.DrawScreenRectBoarder(rect, 3, Color.white);
            }
        }

        public void HandleUnitMovement()
        {
            if(Input.GetMouseButtonDown(0))
            {
                mousePos = Input.mousePosition;
                //Create a ray to shoot it and check if it hits the unit
                Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
                if(Physics.Raycast(ray, out hit))
                {
                    LayerMask layerHit = hit.transform.gameObject.layer;

                    switch (layerHit.value)
                    {
                        case 6: //PlayerUnit Layer
                            SelectUnit(hit.transform, Input.GetKey(KeyCode.LeftShift));
                            break;
                        default: //if non of the above happenes
                            isDragging = true;
                            DeselectUnits();
                            break;
                    }
                }
            }
            if (Input.GetMouseButtonUp(0))
            {
                foreach(Transform child in Player.PlayerManager.instance.playerUnits)
                {
                    foreach(Transform unit in child)
                    {
                        if (isWithinSelectionBounds(unit))
                        {
                            SelectUnit(unit, true);
                        }
                    }
                }
                isDragging = false;
            }

            if (Input.GetMouseButtonDown(1) && HaveSelectedUnits()) 
            {
                //Create a ray to shoot it and check if it hits the unit
                Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
                if (Physics.Raycast(ray, out hit))
                {
                    LayerMask layerHit = hit.transform.gameObject.layer;

                    switch (layerHit.value)
                    {
                        case 6: //PlayerUnit Layer
                            
                            break;
                        default: //if non of the above happenes
                            foreach (Transform unit in selectedUnits) 
                            { 
                                PlayerUnit pU = unit.GetComponent<PlayerUnit>();
                                pU.MoveUnits(hit.point);
                            }
                            break;
                    }
                }
            }
        }

        private void SelectUnit(Transform unit, bool canMultiselect = false)
        {
            if (!canMultiselect)
            {
                DeselectUnits();
            }
            selectedUnits.Add(unit);
            //Highlight the object if it`s been selected
            unit.Find("Highlight").gameObject.SetActive(true);
            Debug.Log("Hit");
        }

        private void DeselectUnits()
        {
            for(int i = 0; i < selectedUnits.Count; i++)
            {
                selectedUnits[i].Find("Highlight").gameObject.SetActive(false);
            }
            selectedUnits.Clear();
        }

        private bool isWithinSelectionBounds(Transform transForm)
        {
            if (!isDragging)
            {
                return false;
            }

            Camera cam = Camera.main;
            Bounds viewPortBounds = MultiSelection.GetViewportBounds(cam, mousePos, Input.mousePosition);
            return viewPortBounds.Contains(cam.WorldToViewportPoint(transForm.position));
        }

        private bool HaveSelectedUnits()
        {
            if (selectedUnits.Count > 0)
            {
                return true;
            }
            else 
            { 
                return false;
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
    }
}
