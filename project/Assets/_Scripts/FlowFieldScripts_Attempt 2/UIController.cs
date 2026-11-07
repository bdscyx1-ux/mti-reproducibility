using System.Collections;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

public class UIController : MonoBehaviour
{
    public GameObject unitController;

    private int currentUnitNum = 0;
    private Text unitNumText;

    // Start is called before the first frame update
    void Start()
    {
        unitNumText = GetComponent<Text>();
    }

    // Update is called once per frame
    void Update()
    {
        currentUnitNum = unitController.GetComponent<UnitController>().unitsInGame.Count;
        unitNumText.text = "Current units in Game: " + currentUnitNum;
        //Debug.Log(currentUnitNum);
    }
}
